"""Guards the TestFlight prerequisites: privacy manifests, the export-compliance key and the upload options."""

import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APPLE = ROOT / "apple"
# Target -> source folder, for every bundle that ships in the app.
MANIFESTS = {
    "FentonHome": "Apps/iOS",
    "FentonHomeWidgets": "Apps/Widgets",
    "FentonHomeNotificationService": "Apps/NotificationService",
    "FentonHomeNotificationContent": "Apps/NotificationContent",
}


class TestFlightPrerequisites(unittest.TestCase):
    def manifest(self, folder: str) -> dict:
        path = APPLE / folder / "PrivacyInfo.xcprivacy"
        self.assertTrue(path.is_file(), f"missing {path}")
        return plistlib.loads(path.read_bytes())

    def test_every_bundle_has_a_manifest_that_declares_no_tracking(self) -> None:
        for target, folder in MANIFESTS.items():
            data = self.manifest(folder)
            self.assertIs(data["NSPrivacyTracking"], False, target)
            self.assertEqual(data["NSPrivacyTrackingDomains"], [], target)
            self.assertEqual(data["NSPrivacyCollectedDataTypes"], [], target)
            for api in data["NSPrivacyAccessedAPITypes"]:
                self.assertTrue(api["NSPrivacyAccessedAPITypeReasons"], f"{target} {api}")

    def test_manifests_are_not_excluded_from_their_target(self) -> None:
        project = (APPLE / "project.yml").read_text()
        for target, folder in MANIFESTS.items():
            self.assertRegex(project, rf"(?m)^  {target}:", target)
            self.assertIn(f"- path: {folder}\n", project, f"{target} no longer compiles {folder}")
        self.assertNotRegex(project, r"(?i)excludes?:[^\n]*xcprivacy")

    def test_app_declares_exempt_encryption(self) -> None:
        project = (APPLE / "project.yml").read_text()
        self.assertRegex(project, r"(?m)^\s+ITSAppUsesNonExemptEncryption: false\s*$")

    def test_upload_options_upload_to_app_store_connect(self) -> None:
        data = plistlib.loads((ROOT / "tools/release/ExportOptions-testflight.plist").read_bytes())
        self.assertEqual(data["method"], "app-store-connect")
        self.assertEqual(data["destination"], "upload")
        self.assertEqual(data["teamID"], "3Q9X8JX23S")

    def test_no_bundle_reads_or_declares_disk_space(self) -> None:
        # Owner, 2026-10-29: the Storage sensor was dropped. Apple's display reason 85F4.1 forbids sending disk space
        # off the device, and no reason covers reporting it to the person's server.
        for target, folder in MANIFESTS.items():
            declared = {a["NSPrivacyAccessedAPIType"] for a in self.manifest(folder)["NSPrivacyAccessedAPITypes"]}
            self.assertNotIn("NSPrivacyAccessedAPICategoryDiskSpace", declared, target)

    def test_watch_app_stays_out_of_the_scheme(self) -> None:
        project = (APPLE / "project.yml").read_text()
        scheme = project.split("\nschemes:", 1)[1]
        self.assertIsNone(re.search(r"FentonHomeWatch", scheme))


# MARK: - Required-reason API scan
#
# Apple's list: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
# (symbols per category: .../app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). Apple only
# emails about a missing declaration (ITMS-91053) after upload processing, so this scans our Swift sources instead.
# Matching is deliberately simple: word-boundary regexes on source with comments removed (string literals are kept, so a
# symbol named in a string also counts; that errs toward declaring). It over-reports rather than misses; a false hit on
# an unrelated type's property is fixed by renaming or by narrowing the pattern here with a comment.
CATEGORY_PATTERNS = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": [
        r"\bcreationDate\b", r"\bmodificationDate\b", r"\bfileCreationDate\b", r"\bfileModificationDate\b",
        r"\bcontentModificationDateKey\b", r"\bcreationDateKey\b", r"\bcontentModificationDate\b",
        r"\bNSFileCreationDate\b", r"\bNSFileModificationDate\b", r"\bNSURLContentModificationDateKey\b",
        r"\bNSURLCreationDateKey\b", r"\bgetattrlist(?:bulk|at)?\b", r"\bfgetattrlist\b", r"\bf?stat\(",
        r"\blstat\(", r"\bfstatat\(",
    ],
    "NSPrivacyAccessedAPICategorySystemBootTime": [r"\bsystemUptime\b", r"\bmach_absolute_time\b"],
    "NSPrivacyAccessedAPICategoryDiskSpace": [
        r"\bvolume(?:Available|Total)Capacity\w*", r"\bsystemFreeSize\b", r"\bsystemSize\b",
        r"\bNSFileSystemFreeSize\b", r"\bNSFileSystemSize\b", r"\bf?statv?fs\(", r"\bfstatvfs\(", r"\bstatvfs\(",
    ],
    "NSPrivacyAccessedAPICategoryActiveKeyboards": [r"\bactiveInputModes\b"],
    "NSPrivacyAccessedAPICategoryUserDefaults": [r"\bUserDefaults\b", r"\bNSUserDefaults\b", r"@AppStorage\b"],
}
# The shipped bundles are MANIFESTS (project.yml target -> source folder); the Watch app is not shipped, so it is not
# scanned.
SHIPPED = MANIFESTS


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"(?m)(?<!:)//.*$", "", text)


def package_graph(package_swift: str) -> tuple[dict[str, set[str]], dict[str, str]]:
    """Returns (library target -> direct target deps, product -> target) read from Package.swift."""
    deps: dict[str, set[str]] = {}
    chunks = re.split(r"(?=\.(?:target|testTarget)\()", package_swift)
    names = {m.group(1) for c in chunks if c.startswith(".target(") for m in [re.search(r'name:\s*"(\w+)"', c)] if m}
    for chunk in chunks:
        if not chunk.startswith(".target("):
            continue
        name = re.search(r'name:\s*"(\w+)"', chunk).group(1)
        found: set[str] = set()
        i = chunk.find("dependencies:")
        if i >= 0:
            start = chunk.index("[", i)
            depth = 0
            for j in range(start, len(chunk)):
                depth += {"[": 1, "]": -1}.get(chunk[j], 0)
                if depth == 0:
                    found = {d for d in re.findall(r'"(\w+)"', chunk[start:j]) if d in names}
                    break
        deps[name] = found
    products = dict(re.findall(r'\.library\(name:\s*"(\w+)",\s*targets:\s*\["(\w+)"\]', package_swift))
    return deps, products


def project_links(project_yml: str) -> dict[str, set[str]]:
    """Returns shipped target -> Swift package products it links directly (embedded targets are separate bundles)."""
    links: dict[str, set[str]] = {}
    for target in SHIPPED:
        m = re.search(rf"(?ms)^  {target}:\n(.*?)(?=^  \w+:\n|\Z)", project_yml)
        links[target] = set(re.findall(r"product:\s*(\w+)", m.group(1))) if m else set()
    return links


def swift_files(folder: Path) -> list[Path]:
    return sorted(folder.rglob("*.swift")) if folder.is_dir() else []


def used_categories(files: list[Path]) -> dict[str, tuple[Path, str]]:
    """Returns category -> (first file, matched symbol) for the categories the files use."""
    hits: dict[str, tuple[Path, str]] = {}
    for file in files:
        text = strip_comments(file.read_text(errors="replace"))
        for category, patterns in CATEGORY_PATTERNS.items():
            if category in hits:
                continue
            for pattern in patterns:
                m = re.search(pattern, text)
                if m:
                    hits[category] = (file, m.group(0))
                    break
    return hits


def bundle_sources(bundle: str, graph, products, links, apple: Path = APPLE) -> list[Path]:
    """All Swift sources compiled into the bundle: its app folders (+ Apps/Shared where project.yml adds it) and the
    transitive closure of the package targets it links."""
    folders = [apple / SHIPPED[bundle]]
    if bundle in ("FentonHome", "FentonHomeWidgets"):
        folders.append(apple / "Apps/Shared")
    todo = [products[p] for p in links[bundle] if p in products]
    seen: set[str] = set()
    while todo:
        t = todo.pop()
        if t not in seen:
            seen.add(t)
            todo.extend(graph.get(t, ()))
    files = [f for folder in folders for f in swift_files(folder)]
    for t in sorted(seen):
        files += swift_files(apple / "Sources" / t)
    return files


def undeclared(apple: Path = APPLE) -> list[str]:
    graph, products = package_graph((apple / "Package.swift").read_text())
    links = project_links((apple / "project.yml").read_text())
    problems = []
    for bundle, folder in SHIPPED.items():
        manifest = plistlib.loads((apple / folder / "PrivacyInfo.xcprivacy").read_bytes())
        declared = {a["NSPrivacyAccessedAPIType"] for a in manifest["NSPrivacyAccessedAPITypes"]}
        for category, (file, symbol) in used_categories(bundle_sources(bundle, graph, products, links, apple)).items():
            if category not in declared:
                problems.append(
                    f"{bundle}: {file.relative_to(apple)} uses `{symbol}` ({category}) but {folder}/PrivacyInfo.xcprivacy "
                    f"does not declare it. Add the category and a reason; see .agents/platforms/apple/testflight.md "
                    f"(Required-reason APIs)."
                )
    return problems


class RequiredReasonScan(unittest.TestCase):
    def test_every_used_required_reason_category_is_declared_in_each_bundle(self) -> None:
        self.assertEqual(undeclared(), [])

    def test_bundle_mapping_follows_the_package_graph(self) -> None:
        graph, products = package_graph((APPLE / "Package.swift").read_text())
        links = project_links((APPLE / "project.yml").read_text())
        widgets = {p.parts[-2] for p in bundle_sources("FentonHomeWidgets", graph, products, links) if "Sources" in p.parts}
        self.assertIn("HassTelemetry", widgets)  # via FentonActivityViews -> HassDesign -> HassTelemetry
        self.assertNotIn("HassCore", widgets)
        service = {p.parts[-2] for p in bundle_sources("FentonHomeNotificationService", graph, products, links) if "Sources" in p.parts}
        self.assertIn("HassTelemetry", service)
        self.assertNotIn("HassUI", service)

    def test_scan_names_file_symbol_bundle_and_category_when_a_declaration_is_missing(self) -> None:
        import shutil
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "apple"
            shutil.copytree(APPLE, copy, ignore=shutil.ignore_patterns(".build", "*.xcodeproj", "Tests", "iOSUITests"))
            (copy / "Sources/HassTelemetry/Scratch.swift").write_text("let t = ProcessInfo.processInfo.systemUptime\n")
            problems = undeclared(copy)
        # Four bundles link HassTelemetry; FentonHome already declares system boot time (UKScrollRate uses it), so three are flagged.
        self.assertEqual(len(problems), 3, problems)
        print("\n".join(problems[:1]))
        self.assertIn("Sources/HassTelemetry/Scratch.swift", problems[0])
        self.assertIn("systemUptime", problems[0])
        self.assertIn("NSPrivacyAccessedAPICategorySystemBootTime", problems[0])


if __name__ == "__main__":
    unittest.main()

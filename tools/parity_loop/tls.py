"""A throwaway, name-constrained certificate for the guard proxy, made at run time and never committed.

The proxy is served over TLS so the candidate's preview (which accepts only an ``https`` origin) can be pointed at it, the same as
the reference. Two certificates are made: a root CA whose critical ``nameConstraints`` permit only ``127.0.0.1`` (IP) and
``localhost`` (DNS), so the root the simulator is told to trust (``simctl keychain add-root-cert``, see
:func:`parity_loop.launch.trust_certificate`) can vouch for nothing else; and a leaf the CA signs for those two names. The CA key is
made in a scratch folder and deleted as soon as the leaf is signed, so it never reaches the run folder. The leaf key sits in the
run's git-ignored folder at mode 0600 until :func:`remove_key` deletes it when the proxy exits. Both are valid for two days. The files
are PEM text under ``.crt`` and ``.key`` names.
"""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .common import Runner, run

#: The OpenSSL config for the CA and the leaf. The CA may sign only loopback names (the constraint is critical, so a verifier that
#: does not understand it refuses the chain).
CONFIG = """[req]
distinguished_name = dn
prompt = no
[dn]
CN = parity-loop guard proxy (throwaway)
[ca_ext]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign
nameConstraints = critical, permitted;IP:127.0.0.1/255.255.255.255, permitted;DNS:localhost
[leaf_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
"""
#: Short on purpose: the certificates are for one run.
VALID_DAYS = 2
CA_NAME, CHAIN_NAME, KEY_NAME = "proxy-ca.crt", "proxy-chain.crt", "proxy-key.key"


class CertificateError(Exception):
    """OpenSSL could not make the certificate; the message carries no key material."""


@dataclass(frozen=True)
class Bundle:
    """What a run keeps: ``ca`` is the root to trust (and the clients' ``--cafile``), ``chain`` the leaf and its CA for the server,
    ``key`` the leaf's private key."""
    ca: Path
    chain: Path
    key: Path


def make_certificate(folder: Path, runner: Runner = run) -> Bundle:
    """Make the CA and the leaf; write ``ca``, ``chain`` and ``key`` into ``folder`` and return them.

    The CA key lives only in a scratch folder that is removed before this returns. The leaf key file is created with mode 0600 before
    OpenSSL writes into it, and any earlier files are replaced.
    """
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    bundle = Bundle(folder / CA_NAME, folder / CHAIN_NAME, folder / KEY_NAME)
    for path in (bundle.ca, bundle.chain, bundle.key):
        path.unlink(missing_ok=True)
    bundle.key.touch(mode=0o600)
    with tempfile.TemporaryDirectory() as scratch:
        work = Path(scratch)
        (work / "openssl.cnf").write_text(CONFIG, encoding="utf-8")
        config, ca_key, csr, leaf = str(work / "openssl.cnf"), str(work / "ca.key"), str(work / "leaf.csr"), work / "leaf.crt"
        curve = ["-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-sha256"]
        steps = [
            ["openssl", "req", "-x509", *curve, "-days", str(VALID_DAYS), "-config", config, "-extensions", "ca_ext",
             "-keyout", ca_key, "-out", str(bundle.ca)],
            ["openssl", "req", "-new", *curve, "-config", config, "-keyout", str(bundle.key), "-out", csr],
            ["openssl", "x509", "-req", "-in", csr, "-CA", str(bundle.ca), "-CAkey", ca_key, "-set_serial", "1", "-sha256",
             "-days", str(VALID_DAYS), "-extfile", config, "-extensions", "leaf_ext", "-out", str(leaf)],
        ]
        for argv in steps:
            result = runner(argv)
            if result.code != 0:
                remove_key(bundle)
                raise CertificateError(f"openssl could not make the proxy certificate (exit {result.code})")
        if not leaf.is_file() or not bundle.ca.is_file() or bundle.key.stat().st_size == 0:
            remove_key(bundle)
            raise CertificateError("openssl wrote no certificate")
        bundle.chain.write_text(leaf.read_text(encoding="utf-8") + bundle.ca.read_text(encoding="utf-8"), encoding="utf-8")
    os.chmod(bundle.key, 0o600)
    return bundle


def remove_key(bundle: Bundle) -> None:
    """Delete the leaf private key (called when the proxy exits, and on a failed make)."""
    bundle.key.unlink(missing_ok=True)

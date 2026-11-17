# Data flow session

> **What:** a document data source that asks Home Assistant for data, runs a closed list of steps and gives rows, a record or a value. **Read when:** you change `ServerUIFlow*` or a flow's service call.

- `sh.pipeline@1`: `ServerUIFlowDecoder` decodes, `ServerUIFlowCompiler` proves the steps against the authored shapes, `ServerUIFlowEvaluator` runs them, and `ServerUIFlowSession` (`HassCore/ServerUIFlow/ServerUIFlowSession.swift`) publishes the rows into one `ServerUIRowCollection`.
- A flow carries no URL, header or key: a request names a Home Assistant service, and Home Assistant holds the secrets.
- The session reads and calls only through `ServerUIFlowHost`. The app's host reads the one `EntityStore` and calls through `HassConnection.callServiceReturningResult(_:_:target:data:timeout:)`, the one call path for a service that answers; the flow's own `timeoutSeconds` is that call's timeout.
- A flow over held entities waits for the first states instead of drawing them unavailable, and a result keeps showing while it runs again (no blank on reconnect).
- Tests: `ServerUIFlowSessionTests`, `ServerUIPipelineCorpusTests`.

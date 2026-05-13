"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { LspClient } = require("../lsp_client");
const { createPythonProcessEnv, resolvePythonEnvironment } = require("./python_env");

const ADAPTER_NAME = "pyright";
const ADAPTER_SOURCE = "local:pyright";
const CONFLICTING_SOURCES = ["Pyright"];
const DEFAULT_TIMEOUT_MS = 20000;
const DEFAULT_SETTLE_MS = 1500;

function configurationValue(workspace, section, key, fallback) {
  try {
    const config = workspace.getConfiguration(section);
    return config && typeof config.get === "function" ? config.get(key, fallback) : fallback;
  } catch (_error) {
    return fallback;
  }
}

function pyrightEnabled(workspace, opts) {
  if (opts && opts.enabled === false) {
    return false;
  }

  return configurationValue(workspace, "localDiagnostics", "pyright.enabled", true) !== false;
}

function pyrightPathFromConfiguration(workspace, opts) {
  if (opts && typeof opts.langserverPath === "string" && opts.langserverPath.trim() !== "") {
    return opts.langserverPath.trim();
  }

  const configuredLangserver = configurationValue(workspace, "localDiagnostics", "pyright.langserverPath", "");
  if (typeof configuredLangserver === "string" && configuredLangserver.trim() !== "") {
    return configuredLangserver.trim();
  }

  if (opts && typeof opts.pyrightPath === "string" && opts.pyrightPath.trim() !== "") {
    return opts.pyrightPath.trim();
  }

  const configured = configurationValue(workspace, "localDiagnostics", "pyright.path", "");
  return typeof configured === "string" && configured.trim() !== "" ? configured.trim() : null;
}

function langserverCandidates(workspace, opts) {
  const candidates = [];
  const configured = pyrightPathFromConfiguration(workspace, opts);
  if (configured) {
    candidates.push(configured);
  }

  for (const envName of ["LOCAL_DIAGNOSTICS_PYRIGHT", "PYRIGHT_PATH"]) {
    if (process.env[envName]) {
      candidates.push(process.env[envName]);
    }
  }

  if (process.env.COC_DATA_HOME) {
    candidates.push(path.join(process.env.COC_DATA_HOME, "extensions", "node_modules", "coc-pyright", "node_modules", ".bin", process.platform === "win32" ? "pyright-langserver.cmd" : "pyright-langserver"));
    candidates.push(path.join(process.env.COC_DATA_HOME, "extensions", "node_modules", "coc-pyright", "node_modules", "pyright", "langserver.index.js"));
  }

  candidates.push(path.join(os.homedir(), ".config", "coc", "extensions", "node_modules", "coc-pyright", "node_modules", ".bin", process.platform === "win32" ? "pyright-langserver.cmd" : "pyright-langserver"));
  candidates.push(path.join(os.homedir(), ".config", "coc", "extensions", "node_modules", "coc-pyright", "node_modules", "pyright", "langserver.index.js"));
  candidates.push("pyright-langserver");

  return Array.from(new Set(candidates));
}

function resolvePyrightLangserver(workspace, opts) {
  for (const candidate of langserverCandidates(workspace, opts)) {
    const isPath = candidate.includes(path.sep) || path.isAbsolute(candidate);
    if (!isPath) {
      return { command: candidate, argsPrefix: ["--stdio"], display: candidate };
    }

    if (!fs.existsSync(candidate)) {
      continue;
    }

    if (candidate.endsWith(".js")) {
      return { command: process.execPath, argsPrefix: [candidate, "--stdio"], display: candidate };
    }

    return { command: candidate, argsPrefix: ["--stdio"], display: candidate };
  }

  return null;
}

function workspaceRoot(workspace, uriTools) {
  if (workspace.root) {
    return workspace.root;
  }

  if (Array.isArray(workspace.workspaceFolders) && workspace.workspaceFolders.length > 0) {
    const file = uriTools.uriToFile(workspace.workspaceFolders[0].uri);
    if (file) {
      return file;
    }
  }

  return process.cwd();
}

function shouldUsePythonFile(file) {
  return Boolean(file && path.extname(file) === ".py" && fs.existsSync(file));
}

function addTarget(targets, uriTools, uriInput) {
  if (!uriInput) {
    return;
  }

  const uri = uriTools.normalizeUri(uriInput);
  const file = uriTools.uriToFile(uri);
  if (!shouldUsePythonFile(file)) {
    return;
  }

  targets.set(uri, file);
}

async function collectTargetsFromNvim(workspace, uriTools, log) {
  const targets = new Map();
  if (!workspace.nvim || typeof workspace.nvim.call !== "function") {
    return targets;
  }

  try {
    const buffers = await workspace.nvim.call("getbufinfo", [{ buflisted: 1 }]);
    if (!Array.isArray(buffers)) {
      return targets;
    }

    for (const info of buffers) {
      if (!info || !info.name) {
        continue;
      }

      addTarget(targets, uriTools, info.name);
    }
  } catch (error) {
    log(`could not list Neovim buffers for ${ADAPTER_NAME}: ${error.message || String(error)}`);
  }

  return targets;
}

function collectTargetsFromTextDocuments(workspace, uriTools) {
  const targets = new Map();
  const documents = Array.isArray(workspace.textDocuments) ? workspace.textDocuments : [];

  for (const document of documents) {
    if (!document || !document.uri) {
      continue;
    }

    if (document.languageId === "python" || path.extname(uriTools.uriToFile(document.uri) || "") === ".py") {
      addTarget(targets, uriTools, document.uri);
    }
  }

  return targets;
}

function configValue(workspace, section, key, fallback) {
  return configurationValue(workspace, section, key, fallback);
}

function analysisSettings(workspace) {
  const severityOverrides = configValue(workspace, "python.analysis", "diagnosticSeverityOverrides", {});
  return {
    autoSearchPaths: configValue(workspace, "python.analysis", "autoSearchPaths", true),
    diagnosticMode: configValue(workspace, "python.analysis", "diagnosticMode", "openFilesOnly"),
    diagnosticSeverityOverrides: severityOverrides && typeof severityOverrides === "object" ? severityOverrides : {},
    extraPaths: configValue(workspace, "python.analysis", "extraPaths", []),
    logLevel: configValue(workspace, "python.analysis", "logLevel", "Information"),
    stubPath: configValue(workspace, "python.analysis", "stubPath", "typings"),
    typeCheckingMode: configValue(workspace, "python.analysis", "typeCheckingMode", "standard"),
    useLibraryCodeForTypes: configValue(workspace, "python.analysis", "useLibraryCodeForTypes", true),
  };
}

function pythonSettings(workspace, pythonEnvironment) {
  const settings = {
    pythonPath: pythonEnvironment && pythonEnvironment.pythonPath
      ? pythonEnvironment.pythonPath
      : configValue(workspace, "python", "pythonPath", "python"),
    analysis: analysisSettings(workspace),
  };

  const configuredVenvPath = configValue(workspace, "python", "venvPath", "");
  if (pythonEnvironment && pythonEnvironment.venvPath) {
    settings.venvPath = pythonEnvironment.venvPath;
  } else if (typeof configuredVenvPath === "string" && configuredVenvPath.trim() !== "") {
    settings.venvPath = configuredVenvPath.trim();
  }

  if (pythonEnvironment && pythonEnvironment.venv) {
    settings.venv = pythonEnvironment.venv;
  }

  return settings;
}

function pyrightSettings(workspace) {
  return {
    disableOrganizeImports: configValue(workspace, "pyright", "disableOrganizeImports", false),
    disableTaggedHints: configValue(workspace, "pyright", "disableTaggedHints", false),
  };
}

function fileUri(file) {
  const resolved = path.resolve(file).replace(/\\/g, "/");
  return `file://${resolved.startsWith("/") ? "" : "/"}${encodeURI(resolved)}`;
}

function diagnosticTimeout(workspace, opts) {
  const configured = Number(configValue(workspace, "localDiagnostics", "pyright.timeoutMs", DEFAULT_TIMEOUT_MS));
  const requested = Number(opts.timeoutMs);
  const value = Number.isFinite(requested) && requested > 0 ? requested : configured;
  return Number.isFinite(value) && value > 0 ? value : DEFAULT_TIMEOUT_MS;
}

function diagnosticSettleMs(workspace, opts) {
  const configured = Number(configValue(workspace, "localDiagnostics", "pyright.settleMs", DEFAULT_SETTLE_MS));
  const requested = Number(opts.settleMs);
  const value = Number.isFinite(requested) && requested >= 0 ? requested : configured;
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_SETTLE_MS;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function collectPythonTargets(workspace, uriTools, opts, log) {
  const targets = new Map();

  if (Array.isArray(opts.files)) {
    for (const file of opts.files) {
      addTarget(targets, uriTools, file);
    }
    return targets;
  }

  for (const [uri, file] of await collectTargetsFromNvim(workspace, uriTools, log)) {
    targets.set(uri, file);
  }

  if (targets.size > 0) {
    return targets;
  }

  return collectTargetsFromTextDocuments(workspace, uriTools);
}

function normalizeLspDiagnostic(diagnostic) {
  const item = {
    range: diagnostic.range,
    message: diagnostic.message,
    severity: diagnostic.severity,
    source: ADAPTER_SOURCE,
  };

  if (diagnostic.code !== undefined && diagnostic.code !== null) {
    item.code = diagnostic.code;
  }

  if (Array.isArray(diagnostic.tags)) {
    item.tags = diagnostic.tags;
  }

  if (Array.isArray(diagnostic.relatedInformation)) {
    item.relatedInformation = diagnostic.relatedInformation;
  }

  if (diagnostic.codeDescription && typeof diagnostic.codeDescription === "object") {
    item.codeDescription = diagnostic.codeDescription;
  }

  return item;
}

async function collectDiagnosticsWithLsp(workspace, uriTools, targets, executable, opts, log) {
  const root = workspaceRoot(workspace, uriTools);
  const timeoutMs = diagnosticTimeout(workspace, opts);
  const settleMs = diagnosticSettleMs(workspace, opts);
  const targetFiles = Array.from(targets.values());
  const pythonEnvironment = resolvePythonEnvironment({
    configValue,
    opts,
    root,
    targetFiles,
    workspace,
  });
  const grouped = new Map();

  if (pythonEnvironment && pythonEnvironment.pythonPath) {
    log(`${ADAPTER_NAME} using Python from ${pythonEnvironment.pythonPath} (${pythonEnvironment.source})`);
  }

  const client = new LspClient(executable.command, executable.argsPrefix, {
    cwd: root,
    env: createPythonProcessEnv(process.env, pythonEnvironment),
    log: (message) => log(`${ADAPTER_NAME} language server: ${message}`),
    onRequest(method, params) {
      if (method === "workspace/configuration") {
        const items = Array.isArray(params && params.items) ? params.items : [];
        return items.map((item) => {
          if (!item || item.section === "python") {
            return pythonSettings(workspace, pythonEnvironment);
          }

          if (item.section === "python.analysis") {
            return analysisSettings(workspace);
          }

          if (item.section === "pyright") {
            return pyrightSettings(workspace);
          }

          return null;
        });
      }

      if (method === "workspace/workspaceFolders") {
        return [{ uri: fileUri(root), name: path.basename(root) || "workspace" }];
      }

      return null;
    },
  });

  try {
    await client.request("initialize", {
      processId: process.pid,
      rootUri: fileUri(root),
      workspaceFolders: [{ uri: fileUri(root), name: path.basename(root) || "workspace" }],
      capabilities: {
        workspace: {
          configuration: true,
          workspaceFolders: true,
          didChangeWatchedFiles: { dynamicRegistration: false },
        },
        textDocument: {
          diagnostic: {
            dynamicRegistration: true,
            relatedDocumentSupport: true,
          },
          publishDiagnostics: {
            tagSupport: { valueSet: [1, 2] },
          },
          synchronization: {
            didSave: true,
          },
        },
        window: {
          workDoneProgress: true,
        },
      },
      initializationOptions: {
        disablePullDiagnostics: false,
      },
    }, timeoutMs);

    client.notify("initialized", {});

    for (const [uri, file] of targets.entries()) {
      client.notify("textDocument/didOpen", {
        textDocument: {
          uri,
          languageId: "python",
          version: 1,
          text: fs.readFileSync(file, "utf8"),
        },
      });
    }

    if (settleMs > 0) {
      await delay(settleMs);
    }

    for (const uri of targets.keys()) {
      const result = await client.request("textDocument/diagnostic", {
        textDocument: { uri },
      }, timeoutMs);
      const items = Array.isArray(result && result.items) ? result.items.map(normalizeLspDiagnostic) : [];
      grouped.set(uri, items);
    }

    return grouped;
  } finally {
    await client.shutdown().catch(() => client.dispose());
  }
}

function applyAdapterDiagnostics(store, requestedUris, grouped) {
  const affected = new Set([...(store.adapterUris.get(ADAPTER_NAME) || []), ...requestedUris]);
  let diagnostics = 0;

  for (const uri of affected) {
    const items = grouped.get(uri) || [];
    diagnostics += items.length;
    store.set(uri, items, { adapter: ADAPTER_NAME });
  }

  return diagnostics;
}

function createPyrightAdapter({ workspace, store, uriTools, log }) {
  let nextRunId = 0;

  async function refreshOpen(optsInput = {}) {
    const opts = optsInput && typeof optsInput === "object" ? optsInput : {};
    const runId = ++nextRunId;

    if (!pyrightEnabled(workspace, opts)) {
      store.clearAdapter(ADAPTER_NAME);
      return { ok: true, adapter: ADAPTER_NAME, skipped: true, reason: "disabled" };
    }

    const targets = await collectPythonTargets(workspace, uriTools, opts, log);
    if (targets.size === 0) {
      store.clearAdapter(ADAPTER_NAME);
      return { ok: true, adapter: ADAPTER_NAME, files: 0, diagnostics: 0 };
    }

    const executable = resolvePyrightLangserver(workspace, opts);
    if (!executable) {
      throw new Error("pyright language server not found");
    }

    const files = Array.from(targets.values());
    log(`running ${ADAPTER_NAME} LSP diagnostics for ${files.length} listed buffer(s): ${executable.display}`);
    const grouped = await collectDiagnosticsWithLsp(workspace, uriTools, targets, executable, opts, log);

    if (runId !== nextRunId) {
      return { ok: true, adapter: ADAPTER_NAME, stale: true };
    }

    const diagnostics = applyAdapterDiagnostics(store, Array.from(targets.keys()), grouped);
    log(`${ADAPTER_NAME} produced ${diagnostics} diagnostics for ${targets.size} listed buffer(s)`);

    return { ok: true, adapter: ADAPTER_NAME, files: targets.size, diagnostics };
  }

  return {
    name: ADAPTER_NAME,
    source: ADAPTER_SOURCE,
    conflictsWithSources: CONFLICTING_SOURCES,
    refreshOpen,
  };
}

module.exports = {
  createPyrightAdapter,
};

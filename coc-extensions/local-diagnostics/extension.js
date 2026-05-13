"use strict";

const { commands, languages, Uri, window, workspace } = require("coc.nvim");

const { createPyrightAdapter } = require("./adapters/pyright");
const { ProcessPool } = require("./process_pool");
const { DiagnosticStore } = require("./store");
const { createUriTools } = require("./uri");

const EXTENSION_NAME = "local-diagnostics";
const COMMAND_PREFIX = "localDiagnostics";

function ok(extra = {}) {
  return Object.assign({ ok: true }, extra);
}

function createExtension() {
  let channel;
  let collection;
  let store;
  let processPool;
  let adapters;
  let refreshEpoch = 0;

  function log(message) {
    if (!channel) {
      return;
    }

    channel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  function fail(error, extra = {}) {
    const message = error && error.message ? error.message : String(error);
    log(`error: ${message}`);
    return Object.assign({ ok: false, error: message }, extra);
  }

  function command(fn) {
    return async (...args) => {
      try {
        return await fn(...args);
      } catch (error) {
        return fail(error);
      }
    };
  }

  async function notifyRefreshComplete(epoch) {
    try {
      if (workspace.nvim && typeof workspace.nvim.command === "function") {
        await workspace.nvim.command(`let g:local_diagnostics_refresh_epoch = ${Number(epoch) || 0}`);
        await workspace.nvim.command("doautocmd <nomodeline> User LocalDiagnosticsRefresh");
      }
    } catch (error) {
      log(`could not notify local diagnostics refresh completion: ${error.message || String(error)}`);
    }
  }

  async function refreshOpen(optsInput = {}) {
    const opts = optsInput && typeof optsInput === "object" ? optsInput : {};
    const epoch = refreshEpoch;
    const refreshOpts = Object.assign({}, opts, { refreshEpoch: epoch });
    const adapterNames = Array.isArray(opts.adapters) && opts.adapters.length > 0 ? opts.adapters : Array.from(adapters.keys());
    const results = [];

    try {
      for (const adapterName of adapterNames) {
        const adapter = adapters.get(adapterName);
        if (!adapter) {
          results.push(fail(`unknown adapter: ${adapterName}`, { adapter: adapterName }));
          continue;
        }

        results.push(await adapter.refreshOpen(Object.assign({}, refreshOpts, opts[adapterName] || {})));
      }
      return ok({ results, lastUpdate: store.status().lastUpdate });
    } finally {
      await notifyRefreshComplete(epoch);
    }
  }

  function adapterMetadata() {
    return Array.from(adapters.values()).map((adapter) => ({
      name: adapter.name,
      source: adapter.source,
      conflictsWithSources: Array.isArray(adapter.conflictsWithSources) ? adapter.conflictsWithSources : [],
    }));
  }

  function activate(context) {
    channel = window.createOutputChannel("Local Diagnostics");
    collection = languages.createDiagnosticCollection(EXTENSION_NAME);
    const uriTools = createUriTools(Uri);
    store = new DiagnosticStore(collection, uriTools, log);
    processPool = new ProcessPool(log);
    adapters = new Map([
      [
        "pyright",
        createPyrightAdapter({
          log,
          isRefreshCurrent: (epoch) => epoch === refreshEpoch,
          processPool,
          store,
          uriTools,
          workspace,
        }),
      ],
    ]);

    context.subscriptions.push(channel, collection);
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.ping`, () => ok({ name: EXTENSION_NAME })));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.set`, command((uri, diagnostics, opts) => ok(store.set(uri, diagnostics, opts)))));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.clear`, command((uri, opts) => {
      refreshEpoch += 1;
      return ok(store.clear(uri, opts));
    })));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.status`, () => ok(Object.assign({ name: EXTENSION_NAME, registeredAdapters: adapterMetadata() }, store.status()))));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.adapters`, () => ok({ adapters: adapterMetadata() })));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.refreshOpen`, command(refreshOpen)));
    context.subscriptions.push(commands.registerCommand(`${COMMAND_PREFIX}.refreshPyrightOpen`, command((opts) => adapters.get("pyright").refreshOpen(opts))));
    log("activated");
  }

  function deactivate() {
    if (processPool) {
      processPool.dispose();
    }

    if (store) {
      store.dispose();
    }
  }

  return {
    activate,
    deactivate,
  };
}

module.exports = {
  createExtension,
};

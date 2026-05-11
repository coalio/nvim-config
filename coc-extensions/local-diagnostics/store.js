"use strict";

const { adapterKey, normalizeDiagnostic } = require("./diagnostic");

class DiagnosticStore {
  constructor(collection, uriTools, log) {
    this.collection = collection;
    this.uriTools = uriTools;
    this.log = log;
    this.tracked = new Map();
    this.adapterUris = new Map();
    this.lastUpdate = null;
  }

  addAdapterUri(key, uri) {
    if (!this.adapterUris.has(key)) {
      this.adapterUris.set(key, new Set());
    }
    this.adapterUris.get(key).add(uri);
  }

  deleteAdapterUri(key, uri) {
    const uris = this.adapterUris.get(key);
    if (!uris) {
      return;
    }

    uris.delete(uri);
    if (uris.size === 0) {
      this.adapterUris.delete(key);
    }
  }

  diagnosticsForUri(uri) {
    const byAdapter = this.tracked.get(uri);
    if (!byAdapter) {
      return [];
    }

    const diagnostics = [];
    for (const items of byAdapter.values()) {
      diagnostics.push(...items);
    }
    return diagnostics;
  }

  updateCollection(uri) {
    const diagnostics = this.diagnosticsForUri(uri);
    if (diagnostics.length === 0) {
      this.tracked.delete(uri);
      this.collection.delete(uri);
      return;
    }

    this.collection.set(uri, diagnostics);
  }

  setAdapterDiagnostics(uri, key, diagnostics) {
    let byAdapter = this.tracked.get(uri);
    if (!byAdapter) {
      byAdapter = new Map();
    }

    if (diagnostics.length > 0) {
      byAdapter.set(key, diagnostics);
      this.tracked.set(uri, byAdapter);
      this.addAdapterUri(key, uri);
    } else {
      byAdapter.delete(key);
      this.deleteAdapterUri(key, uri);
      if (byAdapter.size > 0) {
        this.tracked.set(uri, byAdapter);
      } else {
        this.tracked.delete(uri);
      }
    }

    this.updateCollection(uri);
  }

  set(uriInput, diagnosticsInput, optsInput = {}) {
    const uri = this.uriTools.normalizeUri(uriInput);
    const diagnostics = Array.isArray(diagnosticsInput) ? diagnosticsInput : null;
    const opts = optsInput && typeof optsInput === "object" ? optsInput : {};
    const key = adapterKey(opts);

    if (!diagnostics) {
      throw new Error("diagnostics must be an array");
    }

    const normalized = diagnostics.map((item) => normalizeDiagnostic(item, opts, key));
    this.setAdapterDiagnostics(uri, key, normalized);
    this.lastUpdate = new Date().toISOString();
    this.log(`set ${normalized.length} diagnostics for ${uri} from ${key}`);

    return { uri, adapter: key, count: normalized.length, lastUpdate: this.lastUpdate };
  }

  clearAdapter(key, uriInput) {
    const affected = uriInput ? [this.uriTools.normalizeUri(uriInput)] : Array.from(this.adapterUris.get(key) || []);

    for (const uri of affected) {
      const byAdapter = this.tracked.get(uri);
      if (!byAdapter) {
        continue;
      }

      byAdapter.delete(key);
      this.deleteAdapterUri(key, uri);
      if (byAdapter.size > 0) {
        this.tracked.set(uri, byAdapter);
      } else {
        this.tracked.delete(uri);
      }
      this.updateCollection(uri);
    }

    if (!uriInput) {
      this.adapterUris.delete(key);
    }
  }

  clearUri(uri) {
    const byAdapter = this.tracked.get(uri);
    if (byAdapter) {
      for (const key of byAdapter.keys()) {
        this.deleteAdapterUri(key, uri);
      }
    }

    this.tracked.delete(uri);
    this.collection.delete(uri);
  }

  clear(uriInput, optsInput = {}) {
    const opts = optsInput && typeof optsInput === "object" ? optsInput : {};
    const hasAdapter = Boolean(opts.adapter || opts.source);

    if (uriInput === undefined || uriInput === null || uriInput === "") {
      if (hasAdapter) {
        const key = adapterKey(opts);
        this.clearAdapter(key);
        this.lastUpdate = new Date().toISOString();
        this.log(`cleared diagnostics from ${key}`);
        return { cleared: "adapter", adapter: key, lastUpdate: this.lastUpdate };
      }

      this.collection.clear();
      this.tracked.clear();
      this.adapterUris.clear();
      this.lastUpdate = new Date().toISOString();
      this.log("cleared all diagnostics");
      return { cleared: "all", lastUpdate: this.lastUpdate };
    }

    const uri = this.uriTools.normalizeUri(uriInput);
    if (hasAdapter) {
      const key = adapterKey(opts);
      this.clearAdapter(key, uri);
      this.lastUpdate = new Date().toISOString();
      this.log(`cleared diagnostics for ${uri} from ${key}`);
      return { cleared: uri, adapter: key, lastUpdate: this.lastUpdate };
    }

    this.clearUri(uri);
    this.lastUpdate = new Date().toISOString();
    this.log(`cleared diagnostics for ${uri}`);
    return { cleared: uri, lastUpdate: this.lastUpdate };
  }

  status() {
    const adapters = {};
    let diagnostics = 0;

    for (const byAdapter of this.tracked.values()) {
      for (const [key, items] of byAdapter.entries()) {
        diagnostics += items.length;
        adapters[key] = adapters[key] || { uris: 0, diagnostics: 0 };
        adapters[key].diagnostics += items.length;
      }
    }

    for (const [key, uris] of this.adapterUris.entries()) {
      adapters[key] = adapters[key] || { uris: 0, diagnostics: 0 };
      adapters[key].uris = uris.size;
    }

    return {
      uris: this.tracked.size,
      diagnostics,
      adapters,
      lastUpdate: this.lastUpdate,
    };
  }

  dispose() {
    this.collection.clear();
    this.tracked.clear();
    this.adapterUris.clear();
  }
}

module.exports = {
  DiagnosticStore,
};

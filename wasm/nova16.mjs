/** Import-free NOVA-16 Wasm adapter. Each instance owns an independent machine.
 * Input/output views are short-lived: a VM/compiler call can grow Wasm memory.
 * Use a Worker when integrating synchronous compilation with a browser UI.
 */
export class Nova16 {
  constructor(instance) {
    this.instance = instance;
    this.exports = instance.exports;
    if (this.exports.n16_abi_version() !== 1) throw new Error('Unsupported NOVA-16 Wasm ABI');
  }
  get version() {
    return new TextDecoder().decode(new Uint8Array(this.exports.memory.buffer, this.exports.n16_version_ptr(), this.exports.n16_version_length()));
  }
  call(name, bytes, ...args) {
    if (typeof bytes === 'string') bytes = new TextEncoder().encode(bytes);
    if (!(bytes instanceof Uint8Array)) throw new TypeError('Expected UTF-8 text or Uint8Array');
    if (bytes.length > this.exports.n16_input_capacity()) throw new RangeError('NOVA-16 input limit');
    new Uint8Array(this.exports.memory.buffer, this.exports.n16_input_ptr(), bytes.length).set(bytes);
    this.exports[name](bytes.length, ...args);
    // Obtain a fresh view after the call; memory.grow detaches previous buffers.
    const output = new Uint8Array(this.exports.memory.buffer, this.exports.n16_output_ptr(), this.exports.n16_output_length());
    return JSON.parse(new TextDecoder().decode(output));
  }
  load(rom) { return this.call('n16_load', rom); }
  request(value) { return this.rawRequest(JSON.stringify(value)); }
  rawRequest(text) { return this.call('n16_request', text); }
  setSymbols(text) { return this.call('n16_set_symbols', text); }
  compile(source, {profile = 1, optimize = true} = {}) {
    if (!Number.isInteger(profile) || profile < 1 || profile > 2) throw new RangeError('Profile must be 1 or 2');
    if (typeof optimize !== 'boolean') throw new TypeError('Optimize must be boolean');
    return this.call('n16_compile', source, profile, Number(optimize));
  }
  dispose() { this.exports.n16_dispose(); }
}
export async function createMachine(bytes) {
  const module = bytes instanceof WebAssembly.Module ? bytes : await WebAssembly.compile(bytes);
  if (WebAssembly.Module.imports(module).length) throw new Error('NOVA-16 module must be import-free');
  return new Nova16(await WebAssembly.instantiate(module, {}));
}

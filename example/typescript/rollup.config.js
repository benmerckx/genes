import resolve from 'rollup-plugin-node-resolve'

export default {
  input: 'dist/index.js',
  output: {
    file: 'dist/bundle.js',
    sourcemap: 'inline',
    format: 'iife'
  },
  plugins: [resolve()]
}

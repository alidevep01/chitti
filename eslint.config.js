const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig([
  expoConfig,
  {
    ignores: ['.expo/**', 'dist/**', 'node_modules/**', 'supabase/.temp/**', 'supabase/functions/**'],
  },
  {
    files: ['app/chitti/new.tsx'],
    rules: {
      'react-hooks/incompatible-library': 'off',
    },
  },
]);

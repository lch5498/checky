import path from 'node:path';
import { fileURLToPath } from 'node:url';

import type { NextConfig } from 'next';

const apiDirname = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['@supabase/supabase-js'],
  turbopack: {
    root: path.resolve(apiDirname, '../..'),
  },
};

export default nextConfig;

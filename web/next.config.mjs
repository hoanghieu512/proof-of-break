/** @type {import('next').NextConfig} */
const nextConfig = {
  // The whole page is server-rendered; nothing here needs a client bundle
  // beyond the single refresh button.
  reactStrictMode: true,
};
export default nextConfig;

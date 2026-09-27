import { useEffect } from 'react';

export function PwaBootstrap() {
  useEffect(() => {
    // Expo's `web.output: "single"` export does not render app/+html.tsx.
    // Add the PWA metadata at runtime so browsers can discover the manifest.
    let manifest = document.querySelector<HTMLLinkElement>('link[rel="manifest"]');
    if (!manifest) {
      manifest = document.createElement('link');
      manifest.rel = 'manifest';
      document.head.appendChild(manifest);
    }
    manifest.href = '/manifest.json';

    let themeColor = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!themeColor) {
      themeColor = document.createElement('meta');
      themeColor.name = 'theme-color';
      document.head.appendChild(themeColor);
    }
    themeColor.content = '#C79A33';

    if (!document.querySelector('link[rel="apple-touch-icon"]')) {
      const appleTouchIcon = document.createElement('link');
      appleTouchIcon.rel = 'apple-touch-icon';
      appleTouchIcon.href = '/icons/apple-touch-icon.png';
      document.head.appendChild(appleTouchIcon);
    }

    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      void navigator.serviceWorker.register('/sw.js');
    }
  }, []);
  return null;
}

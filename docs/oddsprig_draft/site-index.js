/* Shared Index menu for every Oddsprig site. This file is identical on every
   site: SITES below is the one source of truth for the Index, and the menu
   markup baked into each page is rebuilt from it on load. */
(() => {
  'use strict';

  // Order, labels and URLs of the Index. Edit here only (and mirror the same
  // list in search-discovery/metadata.py SITES so no-JS pages match).
  const SITES = [
    ['Oddsprig', 'https://oddsprig.com/'],
    ['Tools', 'https://oddsprig.com/tools/'],
    ['Games', 'https://games.oddsprig.com/'],
    ['Learning', 'https://learning.oddsprig.com/'],
    ['Music', 'https://music.oddsprig.com/'],
    ['Marketplace', 'https://marketplace.oddsprig.com/'],
    ['Latent Lands', 'https://latentlands.oddsprig.com/'],
    ['Technologies', 'https://technologies.oddsprig.com/']
  ];

  // Only these exact URLs may be navigated to from a select.
  const destinations = new Set(SITES.map(([, url]) => url));

  // The current site is the entry on this hostname with the longest matching
  // path prefix, so oddsprig.com/tools/... is Tools and the rest of
  // oddsprig.com is Oddsprig. Unknown hosts (previews, localhost) mark nothing.
  const currentIndex = () => {
    const host = location.hostname.toLowerCase().replace(/^www\./, '');
    const path = location.pathname;
    let best = -1;
    let bestLength = -1;
    SITES.forEach(([, url], index) => {
      const target = new URL(url);
      if (target.hostname !== host) return;
      const base = target.pathname.replace(/\/$/, '');
      const matches = base === '' || path === base || path.startsWith(base + '/');
      if (matches && base.length > bestLength) {
        best = index;
        bestLength = base.length;
      }
    });
    return best;
  };

  const buildLinks = (nav, current) => {
    nav.textContent = '';
    SITES.forEach(([label, url], index) => {
      const link = document.createElement('a');
      link.href = url;
      link.textContent = label;
      if (index === current) link.setAttribute('aria-current', 'page');
      nav.appendChild(link);
    });
    if (!nav.hasAttribute('aria-label')) nav.setAttribute('aria-label', 'Site index');
  };

  const buildOptions = select => {
    // Keep the page's own empty prompt option (e.g. "Index") if it has one.
    const first = select.options[0];
    const prompt = first && first.value === '' ? first : new Option('Index', '');
    select.textContent = '';
    select.appendChild(prompt);
    SITES.forEach(([label, url]) => select.appendChild(new Option(label, url)));
    select.value = '';
  };

  const init = () => {
    const current = currentIndex();
    const selects = document.querySelectorAll('select[data-site-index]');
    const menus = document.querySelectorAll('details[data-site-index-menu]');
    // The host theme mirrors even !important colours into a later stylesheet.
    // Its selectors exclude preserved roots and descendants in both themes,
    // including links/options rebuilt below, regardless of script load order.
    const preservePalette = () => {
      menus.forEach(menu => menu.setAttribute('data-oddsprig-preserve', ''));
      selects.forEach(select => select.setAttribute('data-oddsprig-preserve', ''));
    };
    preservePalette();
    const closeMenu = (menu, restoreFocus = false) => {
      menu.open = false;
      if (restoreFocus) menu.querySelector('summary')?.focus();
    };

    menus.forEach(menu => {
      let navs = menu.querySelectorAll('nav.site-index-links');
      if (!navs.length) {
        // Old markup without the links container: add one after the summary.
        const nav = document.createElement('nav');
        nav.className = 'site-index-links';
        menu.appendChild(nav);
        navs = [nav];
      }
      navs.forEach(nav => buildLinks(nav, current));
    });

    selects.forEach(select => {
      buildOptions(select);
      select.addEventListener('change', () => {
        if (destinations.has(select.value)) location.assign(select.value);
      });
    });

    document.addEventListener('click', event => {
      menus.forEach(menu => {
        if (menu.open && !menu.contains(event.target)) {
          closeMenu(menu, menu.contains(document.activeElement));
        }
      });
    });

    document.addEventListener('keydown', event => {
      if (event.key !== 'Escape') return;
      menus.forEach(menu => {
        if (!menu.open) return;
        const restoreFocus = menu.contains(document.activeElement);
        closeMenu(menu, restoreFocus);
        if (restoreFocus) event.preventDefault();
      });
    });

    document.addEventListener('focusin', event => {
      menus.forEach(menu => {
        if (menu.open && !menu.contains(event.target)) closeMenu(menu);
      });
    });

    // Restore the compact prompt and close menus when returning through history.
    window.addEventListener('pageshow', () => {
      preservePalette();
      selects.forEach(select => { select.value = ''; });
      menus.forEach(menu => {
        if (menu.open) closeMenu(menu, menu.contains(document.activeElement));
      });
    });
  };

  // Deferred scripts run after parsing; this also covers a non-deferred load.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();

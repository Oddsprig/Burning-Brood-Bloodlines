/* Shared, local appearance preference. No analytics or external services. */
(() => {
  'use strict';
  if (window.__oddsprigThemeInstalled) return;
  window.__oddsprigThemeInstalled = true;
  const root = document.documentElement, key = 'oddsprig.theme', cookieKey = 'oddsprig_theme';
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  const valid = value => value === 'light' || value === 'dark';
  function stored() {
    let match;try{match=document.cookie.match(/(?:^|;\s*)oddsprig_theme=(light|dark)(?:;|$)/);}catch{}
    if (match) return match[1];
    try { const value = localStorage.getItem(key); return valid(value) ? value : null; } catch { return null; }
  }
  function remember(value) {
    try { localStorage.setItem(key, value); } catch {}
    const shared = location.hostname === 'oddsprig.com' || location.hostname.endsWith('.oddsprig.com');
    try{document.cookie = cookieKey + '=' + value + '; Max-Age=31536000; Path=/; SameSite=Lax' + (shared ? '; Domain=oddsprig.com' : '') + (location.protocol === 'https:' ? '; Secure' : '');}catch{}
  }
  let mode = stored() || (system.matches ? 'dark' : 'light');
  root.dataset.oddsprigTheme = mode;
  if(location.pathname.includes('/electricity/'))root.dataset.oddsprigFamily='electricity';
  let toggle, status, baseline = 'dark', derived;
  const icons = { light:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>', dark:'<path d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5 8.5 8.5 0 1 0 20.5 14.2Z"/>' };
  function emblems() {
    document.querySelectorAll('img.oddsprig-logo,img[src*="oddsprig-logo"],img[src*="oddsprig-mark-on-dark.svg"],img[src*="oddsprig-mark.svg"]').forEach(img => {
      const value = img.getAttribute('src'); if (!value) return;
      const desired = mode === 'dark' ? value.replace(/oddsprig-logo(?:-on-dark)?\.svg/, 'oddsprig-logo-on-dark.svg').replace(/oddsprig-mark\.svg/, 'oddsprig-mark-on-dark.svg') : value.replace(/oddsprig-logo-on-dark\.svg/, 'oddsprig-logo.svg').replace(/oddsprig-mark-on-dark\.svg/, 'oddsprig-mark.svg');
      if (desired !== value) img.setAttribute('src', desired);
    });
  }
  function paint(announce = false) {
    root.dataset.oddsprigTheme = mode;
    if (toggle) {
      const target = mode === 'dark' ? 'light' : 'dark';
      toggle.setAttribute('aria-label', 'Switch to ' + target + ' mode');
      toggle.removeAttribute('aria-pressed');
      toggle.title = 'Switch to ' + target + ' mode';
      toggle.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24">' + icons[target] + '</svg><span>' + (target === 'dark' ? 'Dark mode' : 'Light mode') + '</span>';
    }
    if (announce && status) status.textContent = (mode === 'dark' ? 'Dark' : 'Light') + ' mode enabled.';
    const meta = document.querySelector('meta[name="theme-color"]'); if (meta) meta.content = mode === 'dark' ? '#152227' : '#eeece4';
    emblems();
  }
  // Use the browser's CSS parser, preserving all media/supports rules and original styles.
  function buildLayer() {
    const themeLink=document.querySelector('link[data-oddsprig-theme-style]');
    // A page may load component styles after the common link. Keep this shell last in the cascade.
    const styleNodes=document.head.querySelectorAll('style,link[rel="stylesheet"]');
    if(themeLink&&styleNodes[styleNodes.length-1]!==themeLink)document.head.appendChild(themeLink);
    const themeSheet=themeLink?.sheet;
    if(!themeSheet)return;
    const selected=root.dataset.oddsprigTheme;
    if(derived)derived.media.mediaText='not all';
    delete root.dataset.oddsprigTheme;
    try {
    const bodyStyle=getComputedStyle(document.body),rootStyle=getComputedStyle(root);
    const originalBackground=bodyStyle.backgroundColor,originalRootBackground=rootStyle.backgroundColor;
    const colorCanvas=document.createElement('canvas');colorCanvas.width=colorCanvas.height=1;
    const ctx=colorCanvas.getContext('2d',{willReadFrequently:true});
    if(!ctx){root.dataset.oddsprigTheme=selected;return;}
    const cache=new Map();
    function rgba(value){
      if(cache.has(value))return cache.get(value);
      if(!CSS.supports('color',value)||/\bvar\s*\(/i.test(value)||/^(?:currentcolor|inherit|initial|unset|revert)/i.test(value))return null;
      // An unresolved CSS color must not be mistaken for Canvas's previous fill.
      ctx.fillStyle='#010203';ctx.fillStyle=value;const first=ctx.fillStyle;
      ctx.fillStyle='#040506';ctx.fillStyle=value;if(first!==ctx.fillStyle)return null;
      ctx.clearRect(0,0,1,1);ctx.fillRect(0,0,1,1);
      const pixel=ctx.getImageData(0,0,1,1).data;
      const out=[pixel[0],pixel[1],pixel[2],pixel[3]/255];
      cache.set(value,out);return out;
    }
    const lightness=c=>c?(Math.max(...c.slice(0,3))+Math.min(...c.slice(0,3)))/510:0;
    const luminance=c=>c?c.slice(0,3).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0):0;
    let bg=rgba(originalBackground);if(!bg||bg[3]<.1)bg=rgba(originalRootBackground);
    baseline=root.dataset.oddsprigBase||(bg&&bg[3]>.1?(lightness(bg)>.55?'light':'dark'):(lightness(rgba(bodyStyle.color))<.55?'light':'dark'));
    root.dataset.oddsprigBase=baseline;
    const preserve='.barcode-card,.label-page,.print-sheet,.report-print,#viewport,.viewport,.al-viewport,.studio-art,.game-art,.start-art,.art-grid,.bread-art,.world-map,.chess-board,.checkers-board,.solitaire-table,.board,.picture > svg,.picture > canvas,.dialrow svg,.gearwrap svg,canvas,video';
    document.querySelectorAll(preserve).forEach(el=>{
      if(el.hasAttribute('data-oddsprig-preserve'))return;
      const computed=getComputedStyle(el),ink=computed.color,surface=computed.backgroundColor;
      el.style.setProperty('--oddsprig-original-ink',ink);
      if(surface!=='rgba(0, 0, 0, 0)')el.style.setProperty('--oddsprig-original-surface',surface);
      el.setAttribute('data-oddsprig-preserve','');
    });
    let target='light';
    // Keep semantic hues (for example blue/amber gene categories) while controlling text luminance.
    function tone(c,target){
      const rgb=c.slice(0,3).map(v=>v/255),max=Math.max(...rgb),min=Math.min(...rgb),d=max-min;
      let hue=0,sat=0,l=(max+min)/2;
      if(d){sat=d/(1-Math.abs(2*l-1));hue=max===rgb[0]?((rgb[1]-rgb[2])/d)%6:max===rgb[1]?(rgb[2]-rgb[0])/d+2:(rgb[0]-rgb[1])/d+4;hue=(hue*60+360)%360;}
      sat=Math.min(.75,sat);l=target;
      const chroma=(1-Math.abs(2*l-1))*sat,x=chroma*(1-Math.abs((hue/60)%2-1)),m=l-chroma/2;
      const parts=hue<60?[chroma,x,0]:hue<120?[x,chroma,0]:hue<180?[0,chroma,x]:hue<240?[0,x,chroma]:hue<300?[x,0,chroma]:[chroma,0,x];
      return parts.map(v=>(v+m)*255);
    }
    function converted(color, role) {
      const c = rgba(color); if (!c || c[3] === 0) return color;
      const l = lightness(c), saturation = (Math.max(...c.slice(0,3)) - Math.min(...c.slice(0,3))) / 255;
      let rgb;
      if (role === 'shadow') return 'rgba(12,30,25,' + Math.min(c[3],target === 'light' ? 0.13 : 0.45) + ')';
      if(target===baseline){
        // Native light pages also get soft surfaces, while their authored button/text pairs stay intact.
        if(role!=='background'||saturation>.25||l<.70)return color;
        rgb=l>.95?[244,240,230]:l>.85?[229,237,240]:[214,225,225];
        return 'rgba('+rgb.join(',')+','+c[3]+')';
      }
      if (role === 'background') {
        if (target === 'light') {
          if (l > 0.45 && l < .91 && saturation > 0.18) return color;
          rgb = l < 0.12 ? [238,236,228] : l < 0.30 ? [244,240,230] : l < .80 ? [226,233,229] : [229,237,240];
        } else {
          if (saturation > 0.42 && l < 0.93) return color;
          rgb = l > 0.93 ? [25,43,49] : l > 0.70 ? [34,54,61] : l > 0.42 ? [45,67,71] : c.slice(0,3);
        }
      } else if (role === 'border') {
        rgb = target === 'light' ? (saturation > 0.24 ? [104,132,80] : [161,179,175]) : (saturation > 0.24 ? [136,174,129] : [85,113,116]);
      } else {
        if (target === 'light') {
          if (l < 0.30) return color;
          rgb=saturation>.20?tone(c,.25):l>.82?[30,51,57]:[73,96,91];
        } else {
          if (l > 0.85) return color;
          rgb=saturation>.20?tone(c,.80):l<.35?[232,241,232]:[177,200,200];
        }
      }
      return 'rgba(' + rgb.map(Math.round).join(',') + ',' + (role==='text'?Math.max(c[3],.78):c[3]) + ')';
    }
    const property=/^(?:color|background(?:-color|-image)?|border(?:-(?:top|right|bottom|left))?(?:-color)?|outline(?:-color)?|box-shadow|text-shadow|caret-color|accent-color|text-decoration-color|scrollbar-color)$/;
    const art=/(?:\b(?:canvas|svg|video|img)\b|card-face|card-back|playing-card|sol-card|tableau|foundation|\.(?:stock|waste|pip|suit|rank|piece|square|cell|tile)(?=[\s.#[:>+~)]|$)|matrix-cell|checker-token|chess-piece|sprite|#machine|#waterScene|#stageCanvas)/i;
    function artSelector(selector){
      // A UI container that tests for a canvas is still UI, not the canvas itself.
      let subject='';for(let i=0;i<selector.length;){const match=selector.slice(i).match(/^:(?:has|not)\(/i);if(!match){subject+=selector[i++];continue;}i+=match[0].length;let depth=1,quote='';while(i<selector.length&&depth){const ch=selector[i++];if(quote){if(ch===quote&&selector[i-2]!=='\\')quote='';}else if(ch==='"'||ch==="'")quote=ch;else if(ch==='(')depth++;else if(ch===')')depth--;}}
      return art.test(subject);
    }
    const defined=new Set(),sheets=[];
    function gather(rules){for(const rule of Array.from(rules)){if(rule.style&&(!rule.selectorText||selectorList(rule.selectorText).some(s=>!artSelector(s))))for(const prop of Array.from(rule.style))if(prop.startsWith('--')&&!prop.startsWith('--oddsprig-'))defined.add(prop);if(rule.cssRules)gather(rule.cssRules);if(rule.styleSheet){try{gather(rule.styleSheet.cssRules);}catch{}}}}
    for(const source of Array.from(document.styleSheets)){
      if(source.disabled||source.ownerNode?.id==='oddsprig-theme-derived'||source.href?.includes('/oddsprig-theme.css'))continue;
      try{gather(source.cssRules);sheets.push(source);}catch{}
    }
    const companion=(name,role)=>'--oddsprig-'+role+'-'+name.slice(2);
    function value(input,role){
      let out='';for(let i=0;i<input.length;){
        if(input[i]==='"'||input[i]==="'"){const q=input[i],start=i++;while(i<input.length){if(input[i]===q&&input[i-1]!=='\\'){i++;break;}i++;}out+=input.slice(start,i);continue;}
        const match=input.slice(i).match(/^(#[\da-f]{3,8}\b|[a-zA-Z_-][\w-]*)/);
        if(!match){out+=input[i++];continue;}
        const word=match[0];i+=word.length;
        if(input[i]==='('){const start=i++;let depth=1,q='';for(;i<input.length&&depth;i++){const ch=input[i];if(q){if(ch===q&&input[i-1]!=='\\')q='';}else if(ch==='"'||ch==="'")q=ch;else if(ch==='(')depth++;else if(ch===')')depth--;}
          const whole=word+input.slice(start,i),inside=input.slice(start+1,i-1);
          if(word.toLowerCase()==='url')out+=whole;
          else if(word.toLowerCase()==='var')out+='var('+inside.replace(/^(\s*--[\w-]+)([\s\S]*)$/,(_all,name,rest)=>(defined.has(name.trim())?companion(name.trim(),role):name)+value(rest,role))+')';
          else if(CSS.supports('color',whole)&&rgba(whole))out+=converted(whole,role);
          else out+=word+'('+value(inside,role)+')';
        }else out+=CSS.supports('color',word)?converted(word,role):word;
      }return out;
    }
    function scoped(selector){
      const condition=':where([data-oddsprig-theme="'+target+'"])';
      const rootSelector=/^(\s*(?::(?:where|is)\(\s*(?::root|html)\s*\)|:root\b|html\b))/;
      let result=rootSelector.test(selector)?selector.replace(rootSelector,'$1'+condition):':where(html[data-oddsprig-theme="'+target+'"]) '+selector;
      // Do not recolor generated art, codes, diagrams or their descendants through generic rules.
      const at=result.indexOf('::'),exclude=':not(:where([data-oddsprig-preserve],[data-oddsprig-preserve] *))';
      return at<0?result+exclude:result.slice(0,at)+exclude+result.slice(at);
    }
    function selectorList(value) {
      const out=[];let depth=0,start=0,quote='';
      for(let i=0;i<value.length;i++){const ch=value[i];if(quote){if(ch===quote&&value[i-1]!=='\\')quote='';continue;}if(ch==='"'||ch==="'"){quote=ch;continue;}if(ch==='('||ch==='[')depth++;else if(ch===')'||ch===']')depth--;else if(ch===','&&depth===0){out.push(value.slice(start,i));start=i+1;}}out.push(value.slice(start));return out;
    }
    function walk(rules){
      let result='';for(const rule of Array.from(rules)){
        if(rule.selectorText&&rule.style){
          const selectors=selectorList(rule.selectorText).filter(s=>!artSelector(s));if(!selectors.length)continue;
          let declarations='';
          for(const prop of new Set([...Array.from(rule.style),'background','border','border-top','border-right','border-bottom','border-left','outline'])){
            const original=rule.style.getPropertyValue(prop);if(!original)continue;
            const priority=rule.style.getPropertyPriority(prop)?'!important':'';
            if(prop.startsWith('--')&&!prop.startsWith('--oddsprig-')){
              for(const role of ['background','text','border','shadow'])declarations+=companion(prop,role)+':'+value(original,role)+priority+';';
            }else if(property.test(prop)){
              const role=prop.startsWith('background')?'background':/border|outline/.test(prop)?'border':/shadow/.test(prop)?'shadow':'text';
              declarations+=prop+':'+value(original,role)+priority+';';
            }
          }
          if(declarations)result+=selectors.map(scoped).join(',')+'{'+declarations+'}\n';
        }else if(rule.styleSheet){
          try{let inside=walk(rule.styleSheet.cssRules);if(rule.media?.mediaText)inside='@media '+rule.media.mediaText+'{'+inside+'}';result+=inside;}catch{}
        }else if(rule.cssRules&&/^@(?:media|supports|layer|container)\b/.test(rule.cssText)){
          const heading=rule.cssText.slice(0,rule.cssText.indexOf('{'));const inside=walk(rule.cssRules);if(inside)result+=heading+'{'+inside+'}\n';
        }
      }return result;
    }
    let sheet='';for(target of baseline==='light'?['light','dark']:['light'])for(const source of sheets){try{let inside=walk(source.cssRules);if(source.media?.mediaText)inside='@media '+source.media.mediaText+'{'+inside+'}';sheet+=inside;}catch(error){console.warn('Oddsprig theme: a style rule could not be mirrored.',error);}}
    // The site's strict CSP allows this same-origin stylesheet. No inline style block or weaker CSP is needed.
    const index=themeSheet.cssRules.length;
    themeSheet.insertRule('@media screen{'+sheet+'}',index);
    const next=themeSheet.cssRules[index];
    if(derived){const prior=[...themeSheet.cssRules].indexOf(derived);if(prior>=0)themeSheet.deleteRule(prior);}
    derived=next;
    } finally {
      root.dataset.oddsprigTheme=selected;
      if(derived)derived.media.mediaText='screen';
    }
  }
  function rebuild(){
    try{buildLayer();}catch(error){console.warn('Oddsprig theme: using the base appearance until styles are ready.',error);}
    finally{root.dataset.oddsprigTheme=mode;root.dataset.oddsprigThemeReady='true';paint();}
  }
  function host() {
    const dialogs=document.querySelectorAll('dialog[open]');if(dialogs.length)return dialogs[dialogs.length-1];
    const header=document.querySelector('.oddsprig-nav-wrap,.site-head,.generator-header,.site-header,header.site');
    if(!header)return null;
    return header.querySelector(':scope > .bar > nav,:scope > .wrap > nav,:scope > nav,:scope > .bar,:scope > .wrap')||header;
  }
  function mount() {
    const existing=document.querySelector('.oddsprig-theme-toggle');if(existing){toggle=existing;return true;}
    const target=host();
    const wrap=document.createElement('div');wrap.className=target&&!target.matches('dialog')?'oddsprig-theme-actions':'oddsprig-theme-dock';
    toggle=document.createElement('button');toggle.type='button';toggle.className='oddsprig-theme-toggle';
    toggle.addEventListener('click',()=>{mode=mode==='dark'?'light':'dark';remember(mode);paint(true);});
    wrap.appendChild(toggle);(target||document.body).appendChild(wrap);
    paint();return !!target;
  }
  function ready(){
    rebuild();
    status=document.createElement('span');status.className='oddsprig-theme-status';status.setAttribute('role','status');status.setAttribute('aria-live','polite');document.body.appendChild(status);mount();
    let queued=false;const watcher=new MutationObserver(()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;const target=host();if(!toggle?.isConnected)mount();const wrap=toggle?.parentElement;if(wrap){wrap.className=target&&!target.matches('dialog')?'oddsprig-theme-actions':'oddsprig-theme-dock';if(target&&!target.contains(wrap))target.appendChild(wrap);else if(!target&&wrap.parentElement!==document.body)document.body.appendChild(wrap);}observe();});});
    const watched=new WeakSet();function observe(){for(const target of [document.body,document.querySelector('#app'),document.querySelector('#__next'),host(),host()?.parentElement,...document.querySelectorAll('dialog')])if(target&&!watched.has(target)){watched.add(target);watcher.observe(target,{childList:true,...(target.matches('dialog')?{attributes:true,attributeFilter:['open']}:{})});}}
    observe();
    let styleQueued=false;
    function stylesChanged(){if(styleQueued)return;styleQueued=true;requestAnimationFrame(()=>{styleQueued=false;rebuild();});}
    new MutationObserver(records=>{if(records.some(record=>record.type==='characterData'||record.type==='attributes'||[...record.addedNodes,...record.removedNodes].some(n=>n.nodeType===1&&(n.matches('style,link[rel="stylesheet"]')||n.querySelector?.('style,link[rel="stylesheet"]')))))stylesChanged();}).observe(document.head,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['href','media','disabled']});
    document.addEventListener('load',event=>{if(event.target?.matches?.('link[rel="stylesheet"]'))stylesChanged();},true);
    window.addEventListener('load',rebuild,{once:true});
    window.addEventListener('focus',()=>{const choice=stored();if(choice&&choice!==mode){mode=choice;paint();}});
    window.addEventListener('pageshow',()=>{const choice=stored();if(choice&&choice!==mode){mode=choice;paint();}});
    window.addEventListener('storage',event=>{if(event.key===key&&valid(event.newValue)){mode=stored()||event.newValue;paint();}});
    system.addEventListener('change',event=>{delete root.dataset.oddsprigBase;mode=stored()||(event.matches?'dark':'light');rebuild();});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',ready,{once:true});else ready();
})();

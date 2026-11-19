// Illustrations for the Home screen's Gig Worker / Gig Host tiles
// (Option A of the role-picker mockup). Inline SVG so no asset entries are
// needed; drawn with flutter_svg.

/// Blue toolbox with a wrench and a gold coin: find gigs & earn.
const String kRoleWorkerSvg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
<defs>
<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4C93E0"/><stop offset="1" stop-color="#1F5CA3"/></linearGradient>
<linearGradient id="l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2F72BF"/><stop offset="1" stop-color="#1A4A85"/></linearGradient>
<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFD66B"/><stop offset="1" stop-color="#F0A021"/></linearGradient>
<linearGradient id="s" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E9EEF5"/><stop offset="1" stop-color="#9AA7B8"/></linearGradient>
</defs>
<ellipse cx="58" cy="106" rx="40" ry="6" fill="#000000" fill-opacity="0.16"/>
<path d="M44 42v-9a7 7 0 0 1 7-7h18a7 7 0 0 1 7 7v9" fill="none" stroke="#173F70" stroke-width="7" stroke-linecap="round"/>
<rect x="16" y="40" width="88" height="62" rx="12" fill="url(#b)"/>
<rect x="16" y="40" width="88" height="22" rx="12" fill="url(#l)"/>
<rect x="16" y="54" width="88" height="8" fill="url(#l)"/>
<rect x="16" y="61" width="88" height="3" fill="#123B6A" fill-opacity="0.55"/>
<rect x="23" y="45" width="34" height="5" rx="2.5" fill="#FFFFFF" fill-opacity="0.35"/>
<rect x="53" y="56" width="14" height="13" rx="3.5" fill="url(#g)"/>
<g transform="rotate(-38 62 84)">
<rect x="34" y="80" width="46" height="9" rx="4.5" fill="url(#s)"/>
<path d="M78 72a11 11 0 1 1 0 25l1-8h6v-9h-6z" fill="url(#s)"/>
</g>
<circle cx="97" cy="30" r="15" fill="url(#g)" stroke="#D98B10" stroke-width="2.5"/>
<circle cx="97" cy="30" r="10" fill="none" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="2"/>
<path d="M100.5 24.5c-1-1.2-2.4-1.7-3.8-1.7-2.3 0-3.9 1.2-3.9 3 0 4.1 7.9 2.4 7.9 6.4 0 1.9-1.7 3.2-4.1 3.2-1.7 0-3.3-.7-4.3-1.9M97 20.5v3M97 36v3" fill="none" stroke="#8A5200" stroke-width="2.4" stroke-linecap="round"/>
</svg>''';

/// Storefront with a striped awning and a green "+" badge: post gigs & hire.
const String kRoleHostSvg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
<defs>
<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4C93E0"/><stop offset="1" stop-color="#1F5CA3"/></linearGradient>
<linearGradient id="c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFBF2"/><stop offset="1" stop-color="#F1DDB6"/></linearGradient>
<linearGradient id="n" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4CC98F"/><stop offset="1" stop-color="#23895A"/></linearGradient>
<clipPath id="a"><rect x="14" y="30" width="92" height="20" rx="5"/></clipPath>
</defs>
<ellipse cx="60" cy="106" rx="42" ry="6" fill="#000000" fill-opacity="0.16"/>
<rect x="20" y="44" width="80" height="58" rx="7" fill="url(#c)"/>
<rect x="20" y="96" width="80" height="6" rx="3" fill="#D9BE8A"/>
<g clip-path="url(#a)"><rect x="14.0" y="30" width="11.5" height="20" fill="#F0A830"/><rect x="25.5" y="30" width="11.5" height="20" fill="#FFF6E2"/><rect x="37.0" y="30" width="11.5" height="20" fill="#F0A830"/><rect x="48.5" y="30" width="11.5" height="20" fill="#FFF6E2"/><rect x="60.0" y="30" width="11.5" height="20" fill="#F0A830"/><rect x="71.5" y="30" width="11.5" height="20" fill="#FFF6E2"/><rect x="83.0" y="30" width="11.5" height="20" fill="#F0A830"/><rect x="94.5" y="30" width="11.5" height="20" fill="#FFF6E2"/></g>
<circle cx="19.75" cy="50" r="5.75" fill="#E0941A"/><circle cx="31.25" cy="50" r="5.75" fill="#F5E6C4"/><circle cx="42.75" cy="50" r="5.75" fill="#E0941A"/><circle cx="54.25" cy="50" r="5.75" fill="#F5E6C4"/><circle cx="65.75" cy="50" r="5.75" fill="#E0941A"/><circle cx="77.25" cy="50" r="5.75" fill="#F5E6C4"/><circle cx="88.75" cy="50" r="5.75" fill="#E0941A"/><circle cx="100.25" cy="50" r="5.75" fill="#F5E6C4"/>
<rect x="14" y="30" width="92" height="6" rx="3" fill="#FFFFFF" fill-opacity="0.3"/>
<rect x="28" y="62" width="20" height="16" rx="3" fill="#BFDDFB" stroke="#9BC3EC" stroke-width="2"/>
<rect x="31" y="65" width="6" height="4" rx="1.5" fill="#FFFFFF" fill-opacity="0.8"/>
<rect x="74" y="62" width="18" height="16" rx="3" fill="#BFDDFB" stroke="#9BC3EC" stroke-width="2"/>
<rect x="52" y="64" width="18" height="34" rx="3" fill="url(#b)"/>
<circle cx="66" cy="82" r="1.8" fill="#FFD66B"/>
<rect x="38" y="15" width="44" height="13" rx="5" fill="#1F4D80"/>
<rect x="45" y="20" width="30" height="3" rx="1.5" fill="#FFFFFF" fill-opacity="0.85"/>
<circle cx="99" cy="30" r="13" fill="url(#n)" stroke="#FFFFFF" stroke-width="2.5"/>
<path d="M99 24.5v11M93.5 30h11" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>
</svg>''';

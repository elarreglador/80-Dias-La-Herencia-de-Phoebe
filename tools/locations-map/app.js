/* Fogg Cities visor — Leaflet 1.9.4 vanilla — sin cluster, sin trazo Este */
(() => {
  const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  const FETCH_CANDIDATES = [
    '../../assets/data/locations.json',
    '/assets/data/locations.json',
    './locations.json',
  ];
  const MAX_MERCATOR_LAT = 85.05112878;

  // UI refs
  const filterInput = document.getElementById('filter');
  const cityList = document.getElementById('city-list');
  const counterEl = document.getElementById('counter');
  const bannerEl = document.getElementById('banner');
  const fileInput = document.getElementById('file');
  const dropZone = document.getElementById('drop-zone');
  const metaVersion = document.getElementById('meta-version');

  // Map init — center [20,0] zoom 2, minZoom 2 maxZoom 18
  const map = L.map('map', {
    center: [20, 0],
    zoom: 2,
    minZoom: 2,
    maxZoom: 18,
    worldCopyJump: false,
    zoomControl: true,
    attributionControl: false,
  });
  L.control.attribution({ position: 'bottomleft' }).addTo(map);
  L.tileLayer(TILE_URL, {
    maxZoom: 18,
    attribution: '© OpenStreetMap contributors',
  }).addTo(map);
  map.zoomControl.setPosition('topleft');

  let allCities = [];
  let filteredCities = [];
  let markers = [];
  let selectedCity = null;
  const markerLayer = L.layerGroup().addTo(map);

  function clampLat(lat) {
    return Math.max(-MAX_MERCATOR_LAT, Math.min(MAX_MERCATOR_LAT, lat));
  }

  function showBanner(msg) {
    bannerEl.textContent = msg;
    bannerEl.classList.remove('hidden');
  }
  function hideBanner() {
    bannerEl.textContent = '';
    bannerEl.classList.add('hidden');
  }

  function formatLatLng(lat, lng) {
    return `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
  }

  async function loadCities() {
    let lastErr = null;
    for (const url of FETCH_CANDIDATES) {
      try {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`HTTP ${res.status} at ${url}`);
        const data = await res.json();
        let cities = null;
        let meta = null;
        if (Array.isArray(data)) cities = data;
        else if (Array.isArray(data.cities)) { cities = data.cities; meta = data.meta; }
        else throw new Error('JSON sin array cities');
        if (!Array.isArray(cities) || cities.length === 0 || typeof cities[0].lat !== 'number') throw new Error('cities inválido');
        if (meta && meta.version && metaVersion) metaVersion.textContent = `v${meta.version}`;
        console.log(`[visor] cargadas ${cities.length} ciudades desde ${url}`);
        return cities;
      } catch (e) {
        lastErr = e;
        console.warn(`[visor] fetch fallo ${url}:`, e.message);
      }
    }
    throw lastErr || new Error('No se pudo cargar locations.json');
  }

  function validateAndNormalize(cities) {
    return cities.map((c, idx) => {
      if (c.lat > MAX_MERCATOR_LAT || c.lat < -MAX_MERCATOR_LAT) {
        console.warn(`[visor] lat ${c.lat} clamped`);
        c.lat = clampLat(c.lat);
      }
      return {
        name: c.name || c.asciiname || `City ${idx}`,
        asciiname: c.asciiname || c.name || '',
        lat: Number(c.lat),
        lng: Number(c.lng),
        timezone: c.timezone || 'Unknown/Unknown',
        note: c.note || null,
      };
    });
  }

  function createIcon() {
    return L.divIcon({
      className: 'leaflet-div-icon',
      html: '<div class="fogg-marker"></div>',
      iconSize: [12, 12],
      iconAnchor: [6, 6],
      popupAnchor: [0, -6],
    });
  }

  function popupContent(city) {
    const latlng = formatLatLng(city.lat, city.lng);
    const osm = `https://www.openstreetmap.org/?mlat=${city.lat}&mlon=${city.lng}#map=6/${city.lat}/${city.lng}`;
    const note = city.note ? `<br/><em>${escapeHtml(city.note)}</em>` : '';
    return `
      <div style="min-width:160px">
        <strong>${escapeHtml(city.name)}</strong>${city.asciiname && city.asciiname !== city.name ? ` / ${escapeHtml(city.asciiname)}` : ''}<br/>
        <span style="font-size:11px;color:#666">${latlng}<br/>${escapeHtml(city.timezone)}${note}</span><br/>
        <a href="${osm}" target="_blank" rel="noopener">Ver en OpenStreetMap ↗</a>
      </div>
    `;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (m) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m]));
  }

  function renderMarkers(citiesToRender) {
    markerLayer.clearLayers();
    markers = [];
    citiesToRender.forEach((city) => {
      const m = L.marker([city.lat, city.lng], { icon: createIcon(), title: city.name });
      m.bindPopup(popupContent(city), { maxWidth: 260 });
      m.on('click', () => { highlightList(city); selectedCity = city; });
      markers.push({ city, marker: m });
      m.addTo(markerLayer);
    });
  }

  function highlightList(city) {
    selectedCity = city;
    cityList.querySelectorAll('li').forEach((li) => {
      const isActive = li.dataset.key === `${city.lat},${city.lng},${city.name}`;
      li.classList.toggle('active', isActive);
      if (isActive) li.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    });
  }

  function renderList(citiesToRender) {
    cityList.innerHTML = '';
    if (citiesToRender.length === 0) {
      const li = document.createElement('li');
      li.className = 'empty';
      li.textContent = 'Sin coincidencias';
      cityList.appendChild(li);
      return;
    }
    citiesToRender.forEach((city) => {
      const li = document.createElement('li');
      li.dataset.key = `${city.lat},${city.lng},${city.name}`;
      const nameSpan = document.createElement('div');
      nameSpan.className = 'name';
      nameSpan.textContent = city.asciiname && city.asciiname !== city.name ? `${city.name} / ${city.asciiname}` : city.name;
      const metaSpan = document.createElement('div');
      metaSpan.className = 'meta';
      metaSpan.textContent = `${city.timezone} — ${formatLatLng(city.lat, city.lng)}`;
      li.appendChild(nameSpan);
      li.appendChild(metaSpan);
      li.addEventListener('click', () => {
        map.setView([city.lat, city.lng], 6, { animate: true });
        const found = markers.find((mm) => mm.city.name === city.name && mm.city.lat === city.lat && mm.city.lng === city.lng);
        if (found) found.marker.openPopup();
        highlightList(city);
      });
      if (selectedCity && selectedCity.name === city.name && selectedCity.lat === city.lat) li.classList.add('active');
      cityList.appendChild(li);
    });
  }

  function updateCounter() {
    const total = allCities.length;
    counterEl.textContent = !filterInput.value.trim() ? `${total} ciudades` : `${total} ciudades (${filteredCities.length} filtradas)`;
  }

  let filterTimer = null;
  function applyFilter() {
    const q = filterInput.value.trim().toLowerCase();
    filteredCities = !q ? [...allCities] : allCities.filter((c) => `${c.name} ${c.asciiname} ${c.timezone}`.toLowerCase().includes(q));
    updateCounter();
    renderList(filteredCities);
    renderMarkers(filteredCities);
  }
  filterInput.addEventListener('input', () => {
    clearTimeout(filterTimer);
    filterTimer = setTimeout(applyFilter, 150);
  });

  function renderAll(cities) {
    allCities = validateAndNormalize(cities);
    filteredCities = [...allCities];
    filterInput.value = '';
    selectedCity = null;
    hideBanner();
    updateCounter();
    renderMarkers(filteredCities);
    renderList(filteredCities);
  }

  function handleFile(file) {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = JSON.parse(e.target.result);
        let cities = null;
        if (Array.isArray(data)) cities = data;
        else if (Array.isArray(data.cities)) cities = data.cities;
        else throw new Error('JSON sin cities');
        if (!Array.isArray(cities) || cities.length === 0 || typeof cities[0].lat !== 'number') throw new Error('Array cities inválido');
        renderAll(cities);
        console.log(`[visor] drag&drop cargadas ${cities.length} ciudades`);
      } catch (err) {
        showBanner(`JSON inválido: ${err.message}`);
      }
    };
    reader.readAsText(file);
  }

  fileInput.addEventListener('change', (e) => {
    const f = e.target.files && e.target.files[0];
    if (f) handleFile(f);
  });

  const mapContainer = document.getElementById('map');
  ['dragenter', 'dragover'].forEach((ev) => {
    mapContainer.addEventListener(ev, (e) => { e.preventDefault(); e.stopPropagation(); dropZone.classList.remove('hidden'); });
    document.addEventListener(ev, (e) => e.preventDefault());
  });
  document.addEventListener('dragleave', (e) => {
    if (e.clientX === 0 && e.clientY === 0) dropZone.classList.add('hidden');
  });
  dropZone.addEventListener('dragover', (e) => e.preventDefault());
  dropZone.addEventListener('drop', (e) => {
    e.preventDefault(); e.stopPropagation(); dropZone.classList.add('hidden');
    const f = e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) handleFile(f);
  });
  mapContainer.addEventListener('drop', (e) => {
    e.preventDefault(); dropZone.classList.add('hidden');
    const f = e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) handleFile(f);
  });
  document.addEventListener('drop', (e) => { e.preventDefault(); dropZone.classList.add('hidden'); });

  loadCities().then(renderAll).catch((err) => {
    console.error('[visor] no se pudo cargar locations.json', err);
    showBanner('No se pudo cargar locations.json — arrastra un JSON');
    allCities = []; filteredCities = []; updateCounter(); renderList([]);
    if (location.protocol === 'file:') showBanner('Abre con tools/serve_map.sh — file:// bloqueado por CORS — arrastra un JSON');
  });

  window.__foggVisor = { map, get cities(){return allCities;}, get filtered(){return filteredCities;}, reload: loadCities, renderAll, handleFile };
})();

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
  const seaRoutesFileInput = document.getElementById('sea-routes-file');
  const loadSeaRoutesButton = document.getElementById('load-sea-routes');
  const seaRouteStatus = document.getElementById('sea-route-status');
  const landRoutesFileInput = document.getElementById('land-routes-file');
  const loadLandRoutesButton = document.getElementById('load-land-routes');
  const landRouteStatus = document.getElementById('land-route-status');
  const fakeSeaRoutesFileInput = document.getElementById('fake-sea-routes-file');
  const loadFakeSeaRoutesButton = document.getElementById('load-fake-sea-routes');
  const fakeSeaRouteStatus = document.getElementById('fake-sea-route-status');
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

  // Paneles de rutas: deterministas, por debajo de markerPane (600) y sobre tilePane (200)
  map.createPane('seaRoutesPane').style.zIndex = 401;
  map.createPane('landRoutesPane').style.zIndex = 402;
  map.createPane('fakeSeaRoutesPane').style.zIndex = 403;

  let allCities = [];
  let filteredCities = [];
  let markers = [];
  let selectedCity = null;
  const landRoutesLayer = L.layerGroup().addTo(map);
  const seaRoutesLayer = L.layerGroup().addTo(map);
  const fakeSeaRoutesLayer = L.layerGroup().addTo(map);
  const markerLayer = L.layerGroup().addTo(map);
  const landRouteStyle = {
    pane: 'landRoutesPane',
    renderer: L.svg({ pane: 'landRoutesPane' }),
    className: 'land-route-line',
    color: '#F9A825',
    weight: 3,
    opacity: 0.9,
    dashArray: '8 12',
    interactive: true,
  };
  const seaRouteStyle = {
    pane: 'seaRoutesPane',
    renderer: L.svg({ pane: 'seaRoutesPane' }),
    className: 'sea-route-line',
    color: '#1E88E5',
    weight: 3,
    opacity: 0.9,
    dashArray: '8 12',
    interactive: true,
  };
  const fakeSeaRouteStyle = {
    pane: 'fakeSeaRoutesPane',
    renderer: L.svg({ pane: 'fakeSeaRoutesPane' }),
    className: 'fake-sea-route-line',
    color: '#2E7D32',
    weight: 3,
    opacity: 0.9,
    dashArray: '8 12',
    interactive: true,
  };
  let loadedLandRoutes = [];
  let loadedLandRouteFileName = null;
  let landRouteLoadError = null;
  let loadedSeaRoutes = [];
  let loadedSeaRouteFileName = null;
  let seaRouteLoadError = null;
  let loadedFakeSeaRoutes = [];
  let loadedFakeSeaRouteFileName = null;
  let fakeSeaRouteLoadError = null;

  // Configuración por capa: cada una tiene su layer, estilo, estado y textos
  const seaRouteConfig = {
    layer: seaRoutesLayer,
    style: seaRouteStyle,
    label: 'rutas marítimas',
    errorLabel: 'Rutas marítimas inválidas',
    statusEl: seaRouteStatus,
    buttonEl: loadSeaRoutesButton,
    loadText: 'Cargar rutas marítimas',
    reloadText: 'Recargar rutas marítimas',
    get routes() { return loadedSeaRoutes; },
    get fileName() { return loadedSeaRouteFileName; },
    setLoaded(routes, fileName) { loadedSeaRoutes = routes; loadedSeaRouteFileName = fileName; },
    setError(error) { seaRouteLoadError = error; },
  };
  const landRouteConfig = {
    layer: landRoutesLayer,
    style: landRouteStyle,
    label: 'rutas terrestres',
    errorLabel: 'Rutas terrestres inválidas',
    statusEl: landRouteStatus,
    buttonEl: loadLandRoutesButton,
    loadText: 'Cargar rutas terrestres',
    reloadText: 'Recargar rutas terrestres',
    get routes() { return loadedLandRoutes; },
    get fileName() { return loadedLandRouteFileName; },
    setLoaded(routes, fileName) { loadedLandRoutes = routes; loadedLandRouteFileName = fileName; },
    setError(error) { landRouteLoadError = error; },
  };
  const fakeSeaRouteConfig = {
    layer: fakeSeaRoutesLayer,
    style: fakeSeaRouteStyle,
    label: 'rutas marítimas ficticias',
    errorLabel: 'Rutas marítimas ficticias inválidas',
    statusEl: fakeSeaRouteStatus,
    buttonEl: loadFakeSeaRoutesButton,
    loadText: 'Cargar rutas marítimas ficticias',
    reloadText: 'Recargar rutas marítimas ficticias',
    get routes() { return loadedFakeSeaRoutes; },
    get fileName() { return loadedFakeSeaRouteFileName; },
    setLoaded(routes, fileName) { loadedFakeSeaRoutes = routes; loadedFakeSeaRouteFileName = fileName; },
    setError(error) { fakeSeaRouteLoadError = error; },
  };

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

  function isFiniteNumber(value) {
    return typeof value === 'number' && Number.isFinite(value);
  }

  function isInRange(value, min, max) {
    return isFiniteNumber(value) && value >= min && value <= max;
  }

  function validateRoutes(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('el archivo debe contener un objeto');
    }
    if (data.meta !== undefined) {
      if (!data.meta || typeof data.meta !== 'object' || Array.isArray(data.meta)) {
        throw new Error('meta debe ser un objeto');
      }
      if (Object.prototype.hasOwnProperty.call(data.meta, 'units') && data.meta.units !== 'km') {
        throw new Error('meta.units debe ser km');
      }
      if (Object.prototype.hasOwnProperty.call(data.meta, 'project') && data.meta.project !== 'eu.elarreglador.pf') {
        throw new Error('meta.project no coincide con eu.elarreglador.pf');
      }
    }
    if (!Array.isArray(data.routes) || data.routes.length === 0) {
      throw new Error('routes debe contener al menos una ruta');
    }
    data.routes.forEach((route, index) => {
      const routeLabel = `Ruta ${index + 1}`;
      if (!route || typeof route !== 'object' || Array.isArray(route)) {
        throw new Error(`${routeLabel} no es un objeto`);
      }
      if (typeof route.origin !== 'string' || route.origin.trim() === '') {
        throw new Error(`${routeLabel}: origin es obligatorio`);
      }
      if (typeof route.destination !== 'string' || route.destination.trim() === '') {
        throw new Error(`${routeLabel}: destination es obligatorio`);
      }
      if (!isFiniteNumber(route.distanceKm) || route.distanceKm <= 0) {
        throw new Error(`${routeLabel}: distanceKm debe ser un número positivo`);
      }
      if (Object.prototype.hasOwnProperty.call(route, 'durationHours')
          && (!isFiniteNumber(route.durationHours) || route.durationHours <= 0)) {
        throw new Error(`${routeLabel}: durationHours debe ser un número positivo`);
      }
      [
        ['originLat', -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT],
        ['originLng', -180, 180],
        ['destinationLat', -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT],
        ['destinationLng', -180, 180],
      ].forEach(([field, min, max]) => {
        if (!isInRange(route[field], min, max)) {
          throw new Error(`${routeLabel}: ${field} está fuera de rango`);
        }
      });
      if (!route.geometry || typeof route.geometry !== 'object' || route.geometry.type !== 'LineString') {
        throw new Error(`${routeLabel}: geometry debe ser LineString`);
      }
      if (!Array.isArray(route.geometry.coordinates) || route.geometry.coordinates.length < 2) {
        throw new Error(`${routeLabel}: geometry.coordinates necesita al menos dos puntos`);
      }
      route.geometry.coordinates.forEach((coordinate, coordinateIndex) => {
        if (!Array.isArray(coordinate) || coordinate.length < 2) {
          throw new Error(`${routeLabel}: coordinate ${coordinateIndex + 1} no es un par`);
        }
        if (!isInRange(coordinate[0], -180, 180)) {
          throw new Error(`${routeLabel}: longitud ${coordinateIndex + 1} está fuera de rango`);
        }
        if (!isInRange(coordinate[1], -MAX_MERCATOR_LAT, MAX_MERCATOR_LAT)) {
          throw new Error(`${routeLabel}: latitud ${coordinateIndex + 1} está fuera de rango`);
        }
      });
    });
    return data;
  }

  function mercatorY(lat) {
    return Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
  }

  function mercatorLatitude(y) {
    return (2 * Math.atan(Math.exp(y)) - Math.PI / 2) * 180 / Math.PI;
  }

  function boundaryLatitude(start, end, boundaryLng, unwrappedEndLng) {
    const startY = mercatorY(start[1]);
    const endY = mercatorY(end[1]);
    const ratio = (boundaryLng - start[0]) / (unwrappedEndLng - start[0]);
    return clampLat(mercatorLatitude(startY + (endY - startY) * ratio));
  }

  function splitAntimeridian(coordinates) {
    const segments = [];
    let currentSegment = [];
    coordinates.forEach((coordinate, index) => {
      if (index === 0) {
        currentSegment.push([coordinate[0], coordinate[1]]);
        return;
      }
      const previous = coordinates[index - 1];
      const longitudeDelta = coordinate[0] - previous[0];
      if (Math.abs(longitudeDelta) > 180) {
        const crossesEastward = longitudeDelta < 0;
        const firstBoundary = crossesEastward ? 180 : -180;
        const secondBoundary = crossesEastward ? -180 : 180;
        const unwrappedEndLng = crossesEastward ? coordinate[0] + 360 : coordinate[0] - 360;
        const latitude = boundaryLatitude(previous, coordinate, firstBoundary, unwrappedEndLng);
        currentSegment.push([firstBoundary, latitude]);
        segments.push(currentSegment);
        currentSegment = [[secondBoundary, latitude], [coordinate[0], coordinate[1]]];
      } else {
        currentSegment.push([coordinate[0], coordinate[1]]);
      }
    });
    segments.push(currentSegment);
    return segments;
  }

  function normalizeRoutes(data) {
    return data.routes.map((route) => {
      const longitudeSegments = splitAntimeridian(route.geometry.coordinates);
      return {
        origin: route.origin,
        destination: route.destination,
        distanceKm: route.distanceKm,
        durationHours: isFiniteNumber(route.durationHours) && route.durationHours > 0 ? route.durationHours : null,
        pointCount: route.geometry.coordinates.length,
        leafletSegments: longitudeSegments.map((segment) => segment.map(([lng, lat]) => [lat, lng])),
      };
    });
  }

  function routePopup(route) {
    const hours = route.durationHours ? ` · ${route.durationHours.toFixed(1)} h` : '';
    return `
      <div style="min-width:160px">
        <strong>${escapeHtml(route.origin)} → ${escapeHtml(route.destination)}</strong><br/>
        <span style="font-size:11px;color:#666">${route.distanceKm.toFixed(1)} km${hours} · ${route.pointCount} vértices</span>
      </div>
    `;
  }

  function updateRouteStatus(config) {
    const count = config.routes.length;
    config.statusEl.textContent = config.fileName
      ? `${count} ${config.label} · ${config.fileName}`
      : `${count} ${config.label}`;
    config.buttonEl.textContent = config.fileName ? config.reloadText : config.loadText;
  }

  function createRouteLines(routes, style) {
    return routes.map((route) => {
      const line = L.polyline(route.leafletSegments, style);
      line.bindPopup(routePopup(route), { maxWidth: 260 });
      line.on('mouseover', () => line.setStyle({ weight: 5 }));
      line.on('mouseout', () => line.setStyle({ weight: style.weight }));
      return line;
    });
  }

  function loadRoutes(file, config) {
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const data = JSON.parse(event.target.result);
        validateRoutes(data);
        const routes = normalizeRoutes(data);
        const lines = createRouteLines(routes, config.style);
        config.layer.clearLayers();
        lines.forEach((line) => line.addTo(config.layer));
        config.setLoaded(routes, file.name);
        config.setError(null);
        updateRouteStatus(config);
        hideBanner();
      } catch (error) {
        config.setError(error);
        showBanner(`${config.errorLabel}: ${error.message}`);
      }
    };
    reader.onerror = () => {
      const error = new Error('no se pudo leer el archivo');
      config.setError(error);
      showBanner(`${config.errorLabel}: ${error.message}`);
    };
    reader.readAsText(file);
  }

  function loadSeaRoutes(file) {
    loadRoutes(file, seaRouteConfig);
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
      iconSize: [24, 24],
      iconAnchor: [12, 12],
      popupAnchor: [0, -12],
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

  loadSeaRoutesButton.addEventListener('click', () => {
    seaRoutesFileInput.click();
  });

  seaRoutesFileInput.addEventListener('change', (e) => {
    const f = e.target.files && e.target.files[0];
    if (f) loadRoutes(f, seaRouteConfig);
    e.target.value = '';
  });

  loadLandRoutesButton.addEventListener('click', () => {
    landRoutesFileInput.click();
  });

  landRoutesFileInput.addEventListener('change', (e) => {
    const f = e.target.files && e.target.files[0];
    if (f) loadRoutes(f, landRouteConfig);
    e.target.value = '';
  });

  loadFakeSeaRoutesButton.addEventListener('click', () => {
    fakeSeaRoutesFileInput.click();
  });

  fakeSeaRoutesFileInput.addEventListener('change', (e) => {
    const f = e.target.files && e.target.files[0];
    if (f) loadRoutes(f, fakeSeaRouteConfig);
    e.target.value = '';
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

  updateRouteStatus(seaRouteConfig);
  updateRouteStatus(landRouteConfig);
  updateRouteStatus(fakeSeaRouteConfig);

  loadCities().then(renderAll).catch((err) => {
    console.error('[visor] no se pudo cargar locations.json', err);
    showBanner('No se pudo cargar locations.json — arrastra un JSON');
    allCities = []; filteredCities = []; updateCounter(); renderList([]);
    if (location.protocol === 'file:') showBanner('Abre con tools/serve_map.sh — file:// bloqueado por CORS — arrastra un JSON');
  });

  window.__foggVisor = {
    map,
    get cities() { return allCities; },
    get filtered() { return filteredCities; },
    get seaRoutes() { return loadedSeaRoutes; },
    get seaRouteFileName() { return loadedSeaRouteFileName; },
    get seaRouteError() { return seaRouteLoadError; },
    get landRoutes() { return loadedLandRoutes; },
    get landRouteFileName() { return loadedLandRouteFileName; },
    get landRouteError() { return landRouteLoadError; },
    get fakeSeaRoutes() { return loadedFakeSeaRoutes; },
    get fakeSeaRouteFileName() { return loadedFakeSeaRouteFileName; },
    get fakeSeaRouteError() { return fakeSeaRouteLoadError; },
    seaRoutesLayer,
    landRoutesLayer,
    fakeSeaRoutesLayer,
    reload: loadCities,
    renderAll,
    handleFile,
    loadRoutes,
    loadSeaRoutes,
    validateRoutes,
    normalizeRoutes,
    splitAntimeridian,
  };
})();

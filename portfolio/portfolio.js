(() => {
    const STORAGE_VERSION = 1;
    const SELECTION_URL = "/portfolio/selection.json";

    const normalizeSelection = (value) => {
        if (!value || typeof value !== "object") {
            return { version: STORAGE_VERSION, items: [] };
        }
        if (value.version !== STORAGE_VERSION || !Array.isArray(value.items)) {
            return { version: STORAGE_VERSION, items: [] };
        }
        return value;
    };

    const fetchSelectionJson = async () => {
        try {
            const response = await fetch(SELECTION_URL, { cache: "no-store" });
            if (!response.ok) {
                return { version: STORAGE_VERSION, items: [] };
            }
            return normalizeSelection(await response.json());
        } catch {
            return { version: STORAGE_VERSION, items: [] };
        }
    };

    const byAlbumThenSrc = (a, b) => {
        const albumA = (a.albumTitle || a.album || "").toLowerCase();
        const albumB = (b.albumTitle || b.album || "").toLowerCase();
        if (albumA < albumB) return -1;
        if (albumA > albumB) return 1;
        const srcA = (a.src || "").toLowerCase();
        const srcB = (b.src || "").toLowerCase();
        return srcA.localeCompare(srcB);
    };

    const shuffleInPlace = (array) => {
        for (let i = array.length - 1; i > 0; i -= 1) {
            const j = Math.floor(Math.random() * (i + 1));
            [array[i], array[j]] = [array[j], array[i]];
        }
        return array;
    };

    const buildAlbumLink = (item) => {
        const album = item.album || "/albums/";
        const src = item.src || "";
        const page = Number.isFinite(item.page) ? item.page : Number.parseInt(item.page || "1", 10);
        const url = new URL(album, window.location.origin);
        url.search = "";

        if (page && page > 1) {
            url.searchParams.set("page", String(page));
        }

        if (src) {
            url.searchParams.set("photo", src);
        }

        return `${url.pathname}${url.search}`;
    };

    const render = async () => {
        const selectedShowcase = document.getElementById("portfolio-selected-showcase");
        const emptyState = document.getElementById("portfolio-empty");

        if (!selectedShowcase || !emptyState) {
            return;
        }

        const selectionFromFile = await fetchSelectionJson();
        const selection = shuffleInPlace(
            selectionFromFile.items
                .filter((item) => item && typeof item === "object" && item.src && item.album)
        );

        if (!selection.length) {
            selectedShowcase.hidden = true;
            emptyState.hidden = false;
            return;
        }

        emptyState.hidden = true;
        selectedShowcase.hidden = false;
        selectedShowcase.innerHTML = "";

        selection.forEach((item) => {
            const card = document.createElement("article");
            card.className = "portfolio-card";

            const link = document.createElement("a");
            link.className = "portfolio-card-link";
            link.href = buildAlbumLink(item);

            const img = document.createElement("img");
            img.src = item.src;
            img.alt = item.alt || "Geselecteerde foto";

            const hoverTitle = document.createElement("span");
            hoverTitle.className = "portfolio-hover-title";
            hoverTitle.textContent = item.albumTitle || "Album";

            link.append(img, hoverTitle);
            card.appendChild(link);
            selectedShowcase.appendChild(card);
        });
    };

    document.addEventListener("DOMContentLoaded", render);
})();

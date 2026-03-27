const folderStatus = document.getElementById("folder-status");
const resultStatus = document.getElementById("result-status");
const resultList = document.getElementById("result-list");
const pickFolderButton = document.getElementById("pick-folder");
const albumForm = document.getElementById("album-form");
const albumTitleInput = document.getElementById("album-title");
const albumFileInput = document.getElementById("album-file");
const albumFolderInput = document.getElementById("album-folder");
const albumImagesInput = document.getElementById("album-images");
const coverImageSelect = document.getElementById("cover-image");

let rootDirectoryHandle = null;
let customFileNameTouched = false;
let customFolderNameTouched = false;

const requiredProjectFiles = ["style-album.css", "albumspage.css"];
const placeholderPixel = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==";

const escapeHtml = (value) =>
    value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");

const slugify = (value) =>
    value
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .replace(/-{2,}/g, "-");

const setStatus = (element, message, type = "") => {
    element.textContent = message;
    element.className = "status-text";
    if (type) {
        element.classList.add(`status-${type}`);
    }
};

const listResult = (items) => {
    resultList.innerHTML = "";
    items.forEach((item) => {
        const li = document.createElement("li");
        li.textContent = item;
        resultList.appendChild(li);
    });
};

const updateSuggestedNames = () => {
    const slug = slugify(albumTitleInput.value.trim());
    if (!slug) {
        if (!customFileNameTouched) {
            albumFileInput.value = "";
        }
        if (!customFolderNameTouched) {
            albumFolderInput.value = "";
        }
        return;
    }

    if (!customFileNameTouched) {
        albumFileInput.value = slug;
    }
    if (!customFolderNameTouched) {
        albumFolderInput.value = slug;
    }
};

const refreshCoverImageOptions = () => {
    const files = Array.from(albumImagesInput.files || []);
    coverImageSelect.innerHTML = "";

    if (!files.length) {
        const option = document.createElement("option");
        option.value = "";
        option.textContent = "Kies eerst foto's";
        coverImageSelect.appendChild(option);
        return;
    }

    files.forEach((file, index) => {
        const option = document.createElement("option");
        option.value = file.name;
        option.textContent = file.name;
        if (index === 0) {
            option.selected = true;
        }
        coverImageSelect.appendChild(option);
    });
};

const getFileText = async (directoryHandle, fileName) => {
    const fileHandle = await directoryHandle.getFileHandle(fileName);
    const file = await fileHandle.getFile();
    return file.text();
};

const getNestedFileText = async (directoryHandle, pathSegments) => {
    const segments = [...pathSegments];
    const fileName = segments.pop();
    let currentDirectoryHandle = directoryHandle;

    for (const segment of segments) {
        currentDirectoryHandle = await currentDirectoryHandle.getDirectoryHandle(segment);
    }

    return getFileText(currentDirectoryHandle, fileName);
};

const writeTextFile = async (directoryHandle, fileName, content) => {
    const fileHandle = await directoryHandle.getFileHandle(fileName, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(content);
    await writable.close();
};

const writeNestedTextFile = async (directoryHandle, pathSegments, content) => {
    const segments = [...pathSegments];
    const fileName = segments.pop();
    let currentDirectoryHandle = directoryHandle;

    for (const segment of segments) {
        currentDirectoryHandle = await currentDirectoryHandle.getDirectoryHandle(segment, { create: true });
    }

    await writeTextFile(currentDirectoryHandle, fileName, content);
};

const copyImageFile = async (directoryHandle, file) => {
    const fileHandle = await directoryHandle.getFileHandle(file.storedName, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(file.file);
    await writable.close();
};

const createStoredImageName = (originalName) => {
    const extension = originalName.includes(".") ? `.${originalName.split(".").pop()}` : "";
    const randomPart = crypto.randomUUID().replaceAll("-", "").slice(0, 20);
    return `img-${randomPart}${extension.toLowerCase()}`;
};

const encodePath = (value) => btoa(value);

const generateAlbumPage = ({ title, folderName, imageEntries }) => {
    const photoCards = imageEntries
        .map(
            (entry) => `    <div class="card">
        <img src="${placeholderPixel}" data-encoded-src="${encodePath(`/images/${folderName}/${entry.storedName}`)}" alt="sport foto">
    </div>`
        )
        .join("\n\n");

    return `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)} - NoordzijMaaktFoto's</title>
    <link rel="stylesheet" href="/style-album.css">
    <link rel="icon" type="image/x-icon" href="/favicon.ico">
</head>

<body>

<header>
    <nav>
        <div class="logo">
            <a href="/">
                <img src="/images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo"> 
                NoordzijMaaktFoto's</a>
        </div>
        <input type="checkbox" id="menu-toggle" class="menu-toggle">
        <label for="menu-toggle" class="menu-button">Menu</label>
            <div class="menu">
                <a href="/">Home</a>
                <a href="/overmij/">Over mij</a>
                <a href="/albums/" class="active">Albums</a>
                <a href="/social/">Instagram</a>
                <a href="/contact/">Contact</a>
            </div>
    </nav>
</header>

<div class="container">
    <div class="page-header">
        <h1>${escapeHtml(title)}</h1>
        <a href="/albums/" class="terugknop"><h3>Back</h3></a>
    </div>

<div class="photo-grid">

${photoCards}
</div>
</div>

<footer class="main-footer">
    <div class="footer-container">
        <div class="footer-column brand">
            <div class="footer-logo">
                <img src="/images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo">
                <span>NoordzijMaaktFoto's</span>
                <p>&copy; 2026</p>
            </div>
        </div>

        <div class="footer-column">
            <h3>Navigatie</h3>
            <ul>
                <li><a href="/">Home</a></li>
                <li><a href="/albums/">Albums</a></li>
                <li><a href="/overmij/">Over Mij</a></li>
            </ul>
        </div>

        <div class="footer-column">
            <h3>Support</h3>
            <ul>
                <li><a href="/contact/">Contact</a></li>
                <li><a href="/social/">Instagram</a></li>
            </ul>
        </div>
    </div>
</footer>

<script src="/album-locks.js"></script>
<script src="/album-access.js"></script>
<script src="/album-lightbox.js"></script>

</body>
</html>
`;
};

const buildLegacyRedirect = (routeSlug) => `<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Doorsturen | NoordzijMaaktFoto's</title>
    <link rel="canonical" href="https://noordzijmaaktfotos.nl/${escapeHtml(routeSlug)}/">
    <meta http-equiv="refresh" content="0; url=/${escapeHtml(routeSlug)}/">
    <script>window.location.replace("/${escapeHtml(routeSlug)}/");</script>
</head>
<body>
<p>Je wordt doorgestuurd. <a href="/${escapeHtml(routeSlug)}/">Klik hier als dat niet automatisch gebeurt</a>.</p>
</body>
</html>
`;

const buildAlbumCard = ({ routeSlug, folderName, coverStoredName, title }) => `            <div class="card">
                <a href="/${escapeHtml(routeSlug)}/"><img src="/images/${escapeHtml(folderName)}/${escapeHtml(coverStoredName)}" alt="Something went wrong"></a>
                <a href="/${escapeHtml(routeSlug)}/"><h2>${escapeHtml(title)}</h2></a>
            </div>

`;

const insertAlbumCard = (albumsHtml, cardMarkup, routeSlug) => {
    if (albumsHtml.includes(`href="/${routeSlug}/"`)) {
        throw new Error("Er bestaat al een albumkaart met deze route in /albums/.");
    }

    const marker = '<div class="grid">';
    if (!albumsHtml.includes(marker)) {
        throw new Error("Ik kon de album-grid in /albums/ niet vinden.");
    }

    return albumsHtml.replace(marker, `${marker}\n\n${cardMarkup}`);
};

pickFolderButton.addEventListener("click", async () => {
    if (!window.showDirectoryPicker) {
        setStatus(
            folderStatus,
            "Je browser ondersteunt dit uploadpaneel niet. Gebruik Chrome of Edge op desktop.",
            "error"
        );
        return;
    }

    try {
        const directoryHandle = await window.showDirectoryPicker({ mode: "readwrite" });

        for (const requiredFile of requiredProjectFiles) {
            await directoryHandle.getFileHandle(requiredFile);
        }
        await getNestedFileText(directoryHandle, ["albums", "index.html"]);

        rootDirectoryHandle = directoryHandle;
        setStatus(folderStatus, `Gekoppelde map: ${directoryHandle.name}`, "success");
    } catch (error) {
        if (error.name === "AbortError") {
            return;
        }

        setStatus(
            folderStatus,
            "Deze map lijkt niet de projectmap van de site te zijn, of ik kreeg geen schrijfrechten.",
            "error"
        );
    }
});

albumTitleInput.addEventListener("input", updateSuggestedNames);
albumFileInput.addEventListener("input", () => {
    customFileNameTouched = albumFileInput.value.trim() !== "";
});
albumFolderInput.addEventListener("input", () => {
    customFolderNameTouched = albumFolderInput.value.trim() !== "";
});
albumImagesInput.addEventListener("change", refreshCoverImageOptions);

albumForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    if (!rootDirectoryHandle) {
        setStatus(resultStatus, "Kies eerst je projectmap.", "error");
        return;
    }

    const albumTitle = albumTitleInput.value.trim();
    const routeSlug = slugify(albumFileInput.value.trim().replace(/\.html$/i, ""));
    const folderName = albumFolderInput.value.trim();
    const imageFiles = Array.from(albumImagesInput.files || []);
    const coverFileName = coverImageSelect.value;

    if (!albumTitle || !routeSlug || !folderName || !imageFiles.length || !coverFileName) {
        setStatus(resultStatus, "Vul alle velden in en kies minimaal een foto.", "error");
        return;
    }

    try {
        const existingAlbumHtml = await getNestedFileText(rootDirectoryHandle, ["albums", "index.html"]);
        const imagesDirectoryHandle = await rootDirectoryHandle.getDirectoryHandle("images", { create: true });
        const albumImageDirectoryHandle = await imagesDirectoryHandle.getDirectoryHandle(folderName, { create: true });

        try {
            const albumsDirectoryHandle = await rootDirectoryHandle.getDirectoryHandle("albums");
            await albumsDirectoryHandle.getDirectoryHandle(routeSlug);
            throw new Error("Er bestaat al een paginamap met deze route.");
        } catch (error) {
            if (error.message === "Er bestaat al een paginamap met deze route.") {
                throw error;
            }
        }

        const imageEntries = imageFiles.map((file) => ({
            file,
            sourceName: file.name,
            storedName: createStoredImageName(file.name),
        }));
        const coverEntry = imageEntries.find((entry) => entry.sourceName === coverFileName);

        for (const file of imageEntries) {
            await copyImageFile(albumImageDirectoryHandle, file);
        }

        const albumPage = generateAlbumPage({
            title: albumTitle,
            folderName,
            imageEntries,
        });

        await writeNestedTextFile(rootDirectoryHandle, ["albums", routeSlug, "index.html"], albumPage);
        await writeNestedTextFile(rootDirectoryHandle, [routeSlug, "index.html"], buildLegacyRedirect(`albums/${routeSlug}`));
        await writeTextFile(rootDirectoryHandle, `${routeSlug}.html`, buildLegacyRedirect(`albums/${routeSlug}`));

        const updatedAlbumsHtml = insertAlbumCard(
            existingAlbumHtml,
            buildAlbumCard({
                routeSlug: `albums/${routeSlug}`,
                folderName,
                coverStoredName: coverEntry ? coverEntry.storedName : imageEntries[0].storedName,
                title: albumTitle,
            }),
            `albums/${routeSlug}`
        );

        await writeNestedTextFile(rootDirectoryHandle, ["albums", "index.html"], updatedAlbumsHtml);

        setStatus(resultStatus, "Het album is aangemaakt en toegevoegd aan /albums/.", "success");
        listResult([
            `Nieuwe pagina gemaakt: albums/${routeSlug}/index.html`,
            `Oude links blijven werken via: ${routeSlug}.html en ${routeSlug}/`,
            `Fotomap bijgewerkt: images/${folderName}`,
            "albums/index.html is automatisch aangevuld met het nieuwe album",
            "Vergeet niet je wijzigingen daarna naar je hosting of GitHub te uploaden",
        ]);

        albumForm.reset();
        coverImageSelect.innerHTML = '<option value="">Kies eerst foto\'s</option>';
        customFileNameTouched = false;
        customFolderNameTouched = false;
    } catch (error) {
        setStatus(resultStatus, error.message || "Er ging iets mis tijdens het aanmaken van het album.", "error");
        listResult([]);
    }
});

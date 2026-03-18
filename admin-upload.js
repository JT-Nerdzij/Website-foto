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

const requiredProjectFiles = ["albums.html", "style-album.css", "albumspage.css"];

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
        albumFileInput.value = `${slug}.html`;
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

const writeTextFile = async (directoryHandle, fileName, content) => {
    const fileHandle = await directoryHandle.getFileHandle(fileName, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(content);
    await writable.close();
};

const copyImageFile = async (directoryHandle, file) => {
    const fileHandle = await directoryHandle.getFileHandle(file.name, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(file);
    await writable.close();
};

const generateAlbumPage = ({ title, folderName, imageFiles }) => {
    const photoCards = imageFiles
        .map(
            (file) => `    <div class="card">
        <img src="images/${folderName}/${escapeHtml(file.name)}" alt="sport foto">
    </div>`
        )
        .join("\n\n");

    return `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)} - NoordzijMaaktFoto's</title>
    <link rel="stylesheet" href="style-album.css">
</head>

<body>

<header>
    <nav>
        <div class="logo">
            <a href="index.html">
                <img src="images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo"> 
                NoordzijMaaktFoto's</a>
        </div>
        <input type="checkbox" id="menu-toggle" class="menu-toggle">
        <label for="menu-toggle" class="menu-button">Menu</label>
            <div class="menu">
                <a href="index.html">Home</a>
                <a href="overmij.html">Over mij</a>
                <a href="albums.html"><u>Albums</u></a>
                <a href="schema.html">Schema</a>
                <a href="social.html">Instagram</a>
                <a href="downloads.html">Downloads</a>
                <a href="contact.html">Contact</a>
            </div>
    </nav>
</header>

<div class="container">
    <div class="page-header">
        <h1>${escapeHtml(title)}</h1>
        <a href="albums.html" class="terugknop"><h3>Back</h3></a>
    </div>

<div class="photo-grid">

${photoCards}
</div>
</div>

<footer class="main-footer">
    <div class="footer-container">
        <div class="footer-column brand">
            <div class="footer-logo">
                <img src="images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo">
                <span>NoordzijMaaktFoto's</span>
                <p>&copy; 2026</p>
            </div>
        </div>

        <div class="footer-column">
            <h3>Navigatie</h3>
            <ul>
                <li><a href="index.html">Home</a></li>
                <li><a href="albums.html">Albums</a></li>
                <li><a href="overmij.html">Over Mij</a></li>
                <li><a href="schema.html">Schema</a></li>
            </ul>
        </div>

        <div class="footer-column">
            <h3>Support</h3>
            <ul>
                <li><a href="contact.html">Contact</a></li>
                <li><a href="downloads.html">Downloads</a></li>
                <li><a href="social.html">Instagram</a></li>
            </ul>
        </div>
    </div>
</footer>

<script src="album-lightbox.js"></script>

</body>
</html>
`;
};

const buildAlbumCard = ({ pageFileName, folderName, coverFileName, title }) => `            <div class="card">
                <a href="${escapeHtml(pageFileName)}"><img src="images/${escapeHtml(folderName)}/${escapeHtml(coverFileName)}" alt="Something went wrong"></a>
                <a href="${escapeHtml(pageFileName)}"><h2>${escapeHtml(title)}</h2></a>
            </div>

`;

const insertAlbumCard = (albumsHtml, cardMarkup, pageFileName) => {
    if (albumsHtml.includes(`href="${pageFileName}"`)) {
        throw new Error("Er bestaat al een albumkaart met deze bestandsnaam in albums.html.");
    }

    const marker = '<div class="grid">';
    if (!albumsHtml.includes(marker)) {
        throw new Error("Ik kon de album-grid in albums.html niet vinden.");
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
    const pageFileName = albumFileInput.value.trim().endsWith(".html")
        ? albumFileInput.value.trim()
        : `${albumFileInput.value.trim()}.html`;
    const folderName = albumFolderInput.value.trim();
    const imageFiles = Array.from(albumImagesInput.files || []);
    const coverFileName = coverImageSelect.value;

    if (!albumTitle || !pageFileName || !folderName || !imageFiles.length || !coverFileName) {
        setStatus(resultStatus, "Vul alle velden in en kies minimaal een foto.", "error");
        return;
    }

    try {
        const existingAlbumHtml = await getFileText(rootDirectoryHandle, "albums.html");
        const imagesDirectoryHandle = await rootDirectoryHandle.getDirectoryHandle("images", { create: true });
        const albumImageDirectoryHandle = await imagesDirectoryHandle.getDirectoryHandle(folderName, { create: true });

        for (const file of imageFiles) {
            await copyImageFile(albumImageDirectoryHandle, file);
        }

        const albumPage = generateAlbumPage({
            title: albumTitle,
            folderName,
            imageFiles,
        });

        await writeTextFile(rootDirectoryHandle, pageFileName, albumPage);

        const updatedAlbumsHtml = insertAlbumCard(
            existingAlbumHtml,
            buildAlbumCard({
                pageFileName,
                folderName,
                coverFileName,
                title: albumTitle,
            }),
            pageFileName
        );

        await writeTextFile(rootDirectoryHandle, "albums.html", updatedAlbumsHtml);

        setStatus(resultStatus, "Het album is aangemaakt en toegevoegd aan albums.html.", "success");
        listResult([
            `Nieuwe pagina gemaakt: ${pageFileName}`,
            `Fotomap bijgewerkt: images/${folderName}`,
            `albums.html is automatisch aangevuld met het nieuwe album`,
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

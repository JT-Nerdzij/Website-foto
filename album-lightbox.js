document.addEventListener("DOMContentLoaded", () => {
    const galleryGrid = document.querySelector(".photo-grid");
    const galleryCards = Array.from(document.querySelectorAll(".photo-grid .card"));
    const pageSize = 100;

    if (!galleryGrid || !galleryCards.length) {
        return;
    }

    const totalPages = Math.max(1, Math.ceil(galleryCards.length / pageSize));
    const pageFromUrl = Number.parseInt(new URLSearchParams(window.location.search).get("page") || "1", 10);
    const currentPage = Number.isFinite(pageFromUrl) ? Math.min(Math.max(pageFromUrl, 1), totalPages) : 1;
    const galleryImages = Array.from(document.querySelectorAll(".photo-grid .card img"));

    const updateVisibleCards = () => {
        const startIndex = (currentPage - 1) * pageSize;
        const endIndex = startIndex + pageSize;

        galleryCards.forEach((card, index) => {
            card.classList.toggle("is-hidden", index < startIndex || index >= endIndex);
        });
    };

    const createPageLink = (label, page, { isActive = false, isDisabled = false } = {}) => {
        const link = document.createElement(isDisabled ? "span" : "a");
        link.className = `album-pagination__link${isActive ? " is-active" : ""}${isDisabled ? " is-disabled" : ""}`;
        link.textContent = label;

        if (!isDisabled && !isActive) {
            const url = new URL(window.location.href);
            url.searchParams.set("page", String(page));
            link.href = `${url.pathname}${url.search}`;
        }

        return link;
    };

    const renderPagination = () => {
        if (totalPages <= 1) {
            return;
        }

        const pageHeader = document.querySelector(".page-header");
        const backButton = pageHeader?.querySelector(".terugknop");
        const title = pageHeader?.querySelector("h1");
        const topInfo = document.createElement("div");
        topInfo.className = "album-pagination-top";
        topInfo.textContent = `Pagina ${currentPage} van ${totalPages}`;

        const pagination = document.createElement("nav");
        pagination.className = "album-pagination";
        pagination.setAttribute("aria-label", "Album pagina's");

        const controls = document.createElement("div");
        controls.className = "album-pagination__controls";

        controls.appendChild(
            createPageLink("\u2190", currentPage - 1, { isDisabled: currentPage === 1 })
        );

        for (let page = 1; page <= totalPages; page += 1) {
            controls.appendChild(
                createPageLink(String(page), page, { isActive: page === currentPage })
            );
        }

        controls.appendChild(
            createPageLink("\u2192", currentPage + 1, { isDisabled: currentPage === totalPages })
        );

        pagination.append(controls);

        if (pageHeader && backButton && title) {
            let metaRow = pageHeader.querySelector(".album-meta-row");
            if (!metaRow) {
                metaRow = document.createElement("div");
                metaRow.className = "album-meta-row";
                title.insertAdjacentElement("afterend", metaRow);
            }

            metaRow.append(backButton, topInfo);
        } else {
            galleryGrid.insertAdjacentElement("beforebegin", topInfo);
        }

        galleryGrid.insertAdjacentElement("afterend", pagination);
    };

    updateVisibleCards();
    renderPagination();

    const lightbox = document.createElement("div");
    lightbox.className = "album-lightbox";
    lightbox.setAttribute("aria-hidden", "true");

    const closeButton = document.createElement("button");
    closeButton.className = "album-lightbox__close";
    closeButton.type = "button";
    closeButton.setAttribute("aria-label", "Sluiten");
    closeButton.innerHTML = "<span>x</span>";

    const lightboxContent = document.createElement("div");
    lightboxContent.className = "album-lightbox__content";

    const lightboxImage = document.createElement("img");
    lightboxImage.className = "album-lightbox__image";
    lightboxImage.alt = "";

    const downloadButton = document.createElement("a");
    downloadButton.className = "album-lightbox__download";
    downloadButton.textContent = "Download";
    downloadButton.href = "#";

    lightboxContent.append(lightboxImage, downloadButton);
    lightbox.append(closeButton, lightboxContent);
    document.body.appendChild(lightbox);

    const openLightbox = (image) => {
        const imageUrl = image.currentSrc || image.src;
        const fileName = imageUrl.split("/").pop() || "foto.jpg";
        lightboxImage.src = image.currentSrc || image.src;
        lightboxImage.alt = image.alt || "";
        downloadButton.href = imageUrl;
        downloadButton.setAttribute("download", fileName);
        lightbox.classList.add("is-open");
        lightbox.setAttribute("aria-hidden", "false");
        document.body.classList.add("lightbox-open");
    };

    const closeLightbox = () => {
        lightbox.classList.remove("is-open");
        lightbox.setAttribute("aria-hidden", "true");
        lightboxImage.removeAttribute("src");
        downloadButton.href = "#";
        downloadButton.removeAttribute("download");
        document.body.classList.remove("lightbox-open");
    };

    galleryImages.forEach((image) => {
        image.addEventListener("click", () => openLightbox(image));
    });

    closeButton.addEventListener("click", closeLightbox);

    lightbox.addEventListener("click", (event) => {
        if (event.target === lightbox) {
            closeLightbox();
        }
    });

    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape" && lightbox.classList.contains("is-open")) {
            closeLightbox();
        }
    });
});

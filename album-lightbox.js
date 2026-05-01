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

    const normalizePathname = (value) => {
        if (!value) {
            return "";
        }

        try {
            return new URL(String(value), window.location.origin).pathname;
        } catch {
            return String(value).split("?")[0].split("#")[0];
        }
    };

    const isRealImagePath = (value) => {
        const stringValue = String(value || "");
        return stringValue && !stringValue.startsWith("data:image/");
    };

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

    const scrollToPhotoFromQuery = () => {
        const params = new URLSearchParams(window.location.search);
        const rawPhoto = params.get("photo");
        if (!rawPhoto) {
            return;
        }

        const targetPath = normalizePathname(rawPhoto);
        if (!targetPath) {
            return;
        }

        const attempt = () => {
            for (let index = 0; index < galleryImages.length; index += 1) {
                const image = galleryImages[index];
                const rawSrc = image.currentSrc || image.src || image.getAttribute("src") || "";
                if (!isRealImagePath(rawSrc)) {
                    continue;
                }

                if (normalizePathname(rawSrc) !== targetPath) {
                    continue;
                }

                const desiredPage = Math.floor(index / pageSize) + 1;
                if (desiredPage !== currentPage) {
                    const url = new URL(window.location.href);
                    url.searchParams.set("page", String(desiredPage));
                    window.location.replace(`${url.pathname}${url.search}`);
                    return true;
                }

                const card = image.closest(".card");
                if (card) {
                    card.classList.add("is-portfolio-target");
                    window.setTimeout(() => card.classList.remove("is-portfolio-target"), 1800);
                    card.scrollIntoView({ block: "center", behavior: "smooth" });
                } else {
                    image.scrollIntoView({ block: "center", behavior: "smooth" });
                }
                return true;
            }

            return false;
        };

        const startedAt = Date.now();
        const tick = () => {
            const done = attempt();
            if (done) {
                return;
            }
            if (Date.now() - startedAt > 9000) {
                return;
            }
            window.setTimeout(tick, 200);
        };

        tick();
    };

    scrollToPhotoFromQuery();

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

document.addEventListener("DOMContentLoaded", () => {
    const galleryImages = Array.from(document.querySelectorAll(".photo-grid .card img"));
    if (!galleryImages.length) {
        return;
    }

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

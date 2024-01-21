let fun = async () => {
    const canvas = document.createElement("canvas");
    const body = document.querySelector("body");
    body.appendChild(canvas);

    const ctx = canvas.getContext("2d");
    const res = await Promise.all(Array.from(document.querySelectorAll('.media-card')).map(card => {
        const image = document.createElement("img");
        return new Promise((resolve, reject) => {
            image.src = "https://hentailib.me" + card.getAttribute("data-src");
            image.onload = () => {

                canvas.width = image.naturalWidth;
                canvas.height = image.naturalHeight;
                ctx.drawImage(image, 0, 0, image.naturalWidth, image.naturalHeight);
                const base64 = canvas.toDataURL("image/jpeg");

                resolve({
                    uid: card.href.split('/').pop(),
                    title: card.querySelector(".media-card__title").textContent,
                    // url: "https://hentailib.me" + card.getAttribute("data-src"),
                    cover: base64,
                    data: card.textContent
                });

            };
        });
    }));
    body.removeChild(canvas);
    return res;
}

return await fun();
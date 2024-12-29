let fun = async () => {
    const canvas = document.createElement("canvas");
    const body = document.querySelector("body");
    body.appendChild(canvas);

    const ctx = canvas.getContext("2d");
    const res = await Promise.all(Array.from(document.querySelectorAll('.card-item')).map(card => {
        const image = document.createElement("img");
        return {
            uid: card.getAttribute("data-media-slug"),
            title: card.querySelector(".card-item-caption__main").textContent,
            // url: "https://mangalib.me" + card.getAttribute("data-src"),
            cover: card.querySelector("img").src,
            data: card.textContent
        }
    }));
    console.log(res)
    body.removeChild(canvas);
    return res;
}

return await fun();
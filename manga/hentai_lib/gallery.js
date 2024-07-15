let fun = async () => {
    return await Promise.all(Array.from(document.querySelectorAll('.card-item')).map(card => {
        return {
            uid: card.querySelector("a").href.split('/').pop(),
            title: card.querySelector(".card-item-caption__main").textContent,
            // url: "https://hentailib.me" + card.getAttribute("data-src"),
            cover: card.getAttribute("src"),
            data: card.textContent
        };
    }));
}

return await fun();
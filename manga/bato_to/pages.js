let fun = () => {
    try {

        return Array.from(document.querySelectorAll("div .item")).map((e) => {
            return e.querySelector("img").getAttribute("src");
        });
    } catch (e) {
        return [];
    }
}

fun();
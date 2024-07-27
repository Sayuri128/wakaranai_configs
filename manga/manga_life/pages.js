
let fun = async () => {

    const controller = angular.element(document).controller();
    const pagesCount = controller.CurChapter.Page;
    let currentPage = controller.CurPage;

    const urls = [];
    const pushImg = () => {
        const img = document.querySelector(".img-fluid");
        urls.push(img.src);
    }
    const next = () => {
        const button = document.querySelector(".fas.fa-step-forward");
        button.click();
    }
    while (currentPage != pagesCount) {
        pushImg();
        next();
        currentPage = controller.CurPage;
    }
    pushImg();

    return urls;
}

return await fun();
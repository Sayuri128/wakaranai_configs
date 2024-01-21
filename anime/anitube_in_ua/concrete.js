let fun = () => {
    try {
        const videoSrc = [];
        const select = document.querySelector("#vc-player-selectbox");
        const players = document.querySelector("#rl-lenta-top");
        for (let j = 0; j < players.children.length; j++) {
            const player = players.children[j];
            RalodePlayer.zborka(j, player);
            const group = {
                title: player.textContent,
                videos: []
            };
            for (let i = 0; i < select.children.length; i++) {
                select.value = i;
                RalodePlayer.serie();
                group.videos.push({
                    title: select.children[i].textContent,
                    src: document.querySelector(".playerCode").getElementsByTagName("iframe")[0].src
                });
            }
            videoSrc.push(group);
        }
        return videoSrc;
    } catch (e) {
        return [];
    }
}

return fun();

let getContainer = (selector) => {
    const elements = document.querySelector(selector)?.querySelectorAll("li") || [];
    return Array.from(elements);
};

let getVideoSrc = () => {
    const videoSrc = [];

    const authors = getContainer(".playlists-lists > .playlists-items");
    const videoTypes = getContainer(".playlists-lists > .playlists-items:nth-child(2)");
    const videoPlayers = getContainer(".playlists-lists > .playlists-items:nth-child(3)");
    const videos = getContainer(".playlists-videos > .playlists-items > ul");

    for (let i = 0; i < authors.length; i++) {
        const author = authors[i];
        const authorId = author.getAttribute("data-id");
        if (!author) continue;

        const group = {
            title: author.textContent,
            videos: []
        };

        const filterVideoTypes = () => {
            let videoTypeId = null;

            const filterVideoPlayers = (videoType) => {

                let videoPlayerId = null;

                const filterVideos = (videoPlayer) => {
                    for (const video of videos) {
                        const videoAuthorId = video.getAttribute("data-id");
                        if (videoAuthorId.startsWith(videoPlayerId || videoTypeId || authorId)) {
                            let title = "";
                            if (videoType) title += videoType?.textContent
                            if (videoPlayer) title += ` ${videoPlayer?.textContent}` + " - ";
                            title += ` ${video?.textContent}`;

                            group.videos.push({
                                title: title,
                                src: video.getAttribute("data-file")
                            });
                        }

                    }
                }
                if(videoPlayers.length === 0) {
                    filterVideos(null);
                }
                for (const videoPlayer of videoPlayers) {
                    videoPlayerId = videoPlayer.getAttribute("data-id");
                    if (!videoPlayerId.startsWith(videoTypeId)) continue;
                    filterVideos(videoPlayer);
                }
            }

            if (videoTypes.length === 0) {
                filterVideoPlayers(null);
            }
            for (const videoType of videoTypes) {
                videoTypeId = videoType.getAttribute("data-id");
                if (!videoTypeId.startsWith(authorId)) continue;
                filterVideoPlayers(videoType);
            }
        }

        filterVideoTypes();


        videoSrc.push(group);
    }
    return videoSrc;
};

getVideoSrc();
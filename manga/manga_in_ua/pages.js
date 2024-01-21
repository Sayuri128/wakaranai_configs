let fun = () => {

    const news_id = $("#linkstocomics").data("news_id");

    return {
        action: 'show',
        news_id: $("#comics").data("news_id").toString(),
        user_hash: site_login_hash,
        mod: "load_chapters_image"
    };

}

return fun();
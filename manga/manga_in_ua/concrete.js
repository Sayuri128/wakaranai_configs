let fun = () => {

    const news_id = $("#linkstocomics").data("news_id");
    const news_category = $("#linkstocomics").data("news_category");
    const this_link = news_category === 54 ? $("#linkstocomics").data("this_link") : "";

    const body = {
        action: 'show',
        news_id: news_id.toString(),
        news_category: news_category.toString(),
        this_link: this_link,
        user_hash: site_login_hash
    };

    return body;
}

return fun();
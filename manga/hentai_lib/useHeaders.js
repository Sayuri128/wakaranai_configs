

let getAuth = () => {
    const auth = JSON.parse(localStorage.getItem("auth"));
 
    if (auth) {
        return `${auth.token.token_type} ${auth.token.access_token}`;
    }
    
    return null;
}

return getAuth();
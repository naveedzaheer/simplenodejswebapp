var http = require('http');
const {DefaultAzureCredential, ManagedIdentityCredential} = require('@azure/identity');
const {SecretClient} = require('@azure/keyvault-secrets');

const credential = new ManagedIdentityCredential();

// Replace value with your Key Vault name here
//process.env.NODE_ENV
//const vaultName = "nzfunckv";
const vaultName = process.env.KV_NAME;

const url = `https://${vaultName}.vault.azure.net`;
  
const client = new SecretClient(url, credential);

// Replace value with your secret name here
//const secretName = "MYSQL-URL";
const secretName = process.env.APP_MESSAGE;

var server = http.createServer(function(request, response) {
    response.writeHead(200, {"Content-Type": "text/plain"});
    async function main(){
        // Get the secret we created
        const secret = await client.getSecret(secretName);
        response.write("Here is your secret code to enter quarantine zone: " + secret.value);
        response.end();
    }
    main().catch((err) => {
        response.write(`error code: ${err.code}`);
        response.write(`error message: ${err.message}`);
        response.write(`error stack: ${err.stack}`);
        response.end();
    });
});

var port = process.env.PORT || 1337;
server.listen(port);

console.log("Server running at http://localhost:%d", port);

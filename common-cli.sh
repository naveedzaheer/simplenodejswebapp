az keyvault list-deleted -o table

az keyvault purge --name nzeastus201-kv1
az keyvault purge --name nzmqkv
az keyvault purge --name nz2807win-demo-kv1


az webapp log tail -g nzlineast2-funcdemo-rg -n nzlineast2-demofunc-app
az webapp log tail -g nzlineast2-funcdemo-rg -n nzlineast2dotnetapp 




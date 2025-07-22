
We must build the following registries with the following specifications to verify the artifact streaming conversion scenarios:

Each scenario uses a single layer count and a uniform layer size.
Total registry size is capped at 15 TB (15 × 1024 GB = 15 360 GB).


Registry names follow Azure Container Registry rules: lowercase letters, digits, and hyphens (5–50 chars).
| Registry Name | # Layers | Layer Size | Image Size | # Images | Total Registry Size |
|-------------- | -------- | ---------- | ---------- | -------- | ------------------- |
| acr-5l-50mb | 5 | 50 MB | 250 MB | 62 914 | ~15 TB | 
| acr-5l-100mb | 5 | 100 MB | 500 MB | 31 457 | ~15 TB | 
| acr-5l-300mb | 5 | 300 MB | 1 500 MB | 10 485 | ~15 TB | 
| acr-5l-1gb | 5 | 1 GB | 5 120 MB | 3 072 | ~15 TB | 
| acr-5l-2gb | 5 | 2 GB | 10 240 MB | 1 536 | ~15 TB | 
| acr-20l-50mb | 20 | 50 MB | 1 000 MB | 15 728 | ~15 TB | 
| acr-20l-100mb | 20 | 100 MB | 2 000 MB | 7 864 | ~15 TB | 
| acr-20l-300mb | 20 | 300 MB | 6 000 MB | 2 621 | ~15 TB | 
| acr-20l-1gb | 20 | 1 GB | 20 480 MB | 768 | ~15 TB | 
| acr-20l-2gb | 20 | 2 GB | 40 960 MB | 384 | ~15 TB | 
| acr-50l-50mb | 50 | 50 MB | 2 500 MB | 6 291 | ~15 TB | 
| acr-50l-100mb | 50 | 100 MB | 5 000 MB | 3 145 | ~15 TB | 
| acr-50l-300mb | 50 | 300 MB | 15 000 MB | 1 049 | ~15 TB | 
| acr-50l-1gb | 50 | 1 GB | 51 200 MB | 307 | ~15 TB | 
| acr-50l-2gb | 50 | 2 GB | 102 400 MB | 153 | ~15 TB | 
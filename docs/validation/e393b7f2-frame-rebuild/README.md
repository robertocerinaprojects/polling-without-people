# Frame preparation rebuild, November 10, 2026

An isolated rebuild at commit `e393b7f24940aff87425c4886dbaeba957f0f873` used
the 70 files in [input_sha256.csv](input_sha256.csv). Steps 01–08, including
the optional CES benchmarks, passed. Step 09 also prepared the House model
inputs. This run ended before sampling.

[product_sha256.csv](product_sha256.csv) is a **selected extract** of that
run’s evidence. It includes all 75 Step 01–08 products and four Step 09
preparation products. For 69 of these 79 files the working copy matched the
rebuilt bytes. The ten optional benchmark tables were produced successfully
in the rebuild and were absent from the working copy at the time.

The `09_house_training_cd119.csv` row gives the exact fingerprint of the
2024 House district training table. The columns in this extract describe the
recorded run at the commit above. [Full receipt as recorded](https://github.com/robertocerinaprojects/polling-without-people/blob/c48df55ff9356b8a96db4aa361289fcba5c622ff/docs/validation/e393b7f2-frame-rebuild/rebuild_receipt.json)

SHA-256 of the complete receipt: `713a73b8833470a8dc8fe3184f5a5e32f11c19f439795aa3d143c409ab2597b8`.

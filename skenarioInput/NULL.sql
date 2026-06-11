SELECT *
FROM kontrak_sewa
WHERE tanggal_kembali_aktual IS NULL
LIMIT 1;

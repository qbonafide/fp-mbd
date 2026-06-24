SELECT COUNT(*) AS jumlah_terlambat
FROM Kontrak_Sewa
WHERE id_pelanggan = 8670
AND status_sewa = 'Terlambat';

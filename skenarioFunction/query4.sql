SELECT COUNT(*) AS jumlah_pelanggaran_geofence
FROM Pelanggaran_Geofence pg
JOIN Kontrak_Sewa ks
ON pg.id_sewa = ks.id_sewa
WHERE ks.id_pelanggan = 8670;

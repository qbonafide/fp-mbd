SELECT COUNT(*) AS jumlah_menunggak
FROM Pembayaran pb
JOIN Kontrak_Sewa ks
ON pb.id_sewa = ks.id_sewa
WHERE ks.id_pelanggan = 8670
AND pb.status_pembayaran = 'Menunggak';

SELECT
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun,
    COUNT(DISTINCT CASE
        WHEN ks.status_sewa = 'Terlambat'
        THEN ks.id_sewa
    END) AS jumlah_terlambat,

    COUNT(DISTINCT CASE
        WHEN pb.status_pembayaran = 'Menunggak'
        THEN pb.id_pembayaran
    END) AS jumlah_menunggak,

    COUNT(DISTINCT pg.id_pelanggaran) AS jumlah_geofence

FROM Pelanggan p
JOIN Kontrak_Sewa ks
    ON p.id_pelanggan = ks.id_pelanggan

LEFT JOIN Pembayaran pb
    ON ks.id_sewa = pb.id_sewa

LEFT JOIN Pelanggaran_Geofence pg
    ON ks.id_sewa = pg.id_sewa

GROUP BY
    p.id_pelanggan,
    p.nama_depan,
    p.nama_belakang,
    p.status_akun

HAVING
    jumlah_terlambat > 0
    AND jumlah_menunggak > 0
    AND jumlah_geofence > 0
    AND p.status_akun IN ('Ditangguhkan', 'Diblokir')

LIMIT 10;

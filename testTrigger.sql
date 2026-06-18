USE fp_rental_kendaraan;

SET NAMES utf8mb4 COLLATE utf8mb4_general_ci;

-- =====================================================
-- 1. CEK TRIGGER SUDAH TERPASANG
-- =====================================================
SHOW TRIGGERS
WHERE `Trigger` = 'trg_after_pelanggaran_geofence_insert';


-- =====================================================
-- 2. MULAI TRANSAKSI PENGUJIAN
-- Semua data uji akan dibatalkan di akhir dengan ROLLBACK
-- Kalau ingin data test disimpan, ganti ROLLBACK menjadi COMMIT
-- =====================================================
START TRANSACTION;

-- Simpan batas ID awal agar hasil test bisa difilter tanpa pakai LIKE
SET @min_pelanggaran_id = (SELECT COALESCE(MAX(id_pelanggaran), 0) FROM pelanggaran_geofence);
SET @min_anomali_id = (SELECT COALESCE(MAX(id_anomali), 0) FROM log_anomali);
SET @min_daftar_hitam_id = (SELECT COALESCE(MAX(id_daftar_hitam), 0) FROM daftar_hitam);

SET @kode_test = CONCAT('TEST_TRIGGER_GEOFENCE_', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'));


-- =====================================================
-- 3. PASTIKAN ADA RENTAL AKTIF UNTUK KEBUTUHAN BLACKLIST
-- =====================================================
INSERT INTO komunitas_rental (
    nama_rental,
    kota,
    kontak,
    api_key,
    status_keanggotaan,
    tanggal_bergabung
)
SELECT
    'Rental Test Trigger',
    'Surabaya',
    '081234567890',
    CONCAT('API_TEST_', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
    'Aktif',
    CURDATE()
WHERE NOT EXISTS (
    SELECT 1
    FROM komunitas_rental
    WHERE status_keanggotaan = 'Aktif'
);


-- =====================================================
-- 4. AMBIL DATA PELANGGAN YANG SUDAH PUNYA MINIMAL 2 TRANSAKSI
-- Dipilih pelanggan aktif dan belum punya pelanggaran geofence
-- agar hasil pengujian bersih
-- =====================================================
SELECT ks.id_pelanggan
INTO @id_pelanggan
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
LEFT JOIN pelanggaran_geofence pg ON ks.id_sewa = pg.id_sewa
WHERE p.status_akun = 'Aktif'
GROUP BY ks.id_pelanggan
HAVING COUNT(DISTINCT ks.id_sewa) >= 2
   AND COUNT(pg.id_pelanggaran) = 0
LIMIT 1;


-- Ambil transaksi pertama pelanggan
SELECT id_sewa, id_kendaraan
INTO @id_sewa_1, @id_kendaraan_1
FROM kontrak_sewa
WHERE id_pelanggan = @id_pelanggan
ORDER BY id_sewa ASC
LIMIT 1;


-- Ambil transaksi kedua pelanggan
SELECT id_sewa, id_kendaraan
INTO @id_sewa_2, @id_kendaraan_2
FROM kontrak_sewa
WHERE id_pelanggan = @id_pelanggan
  AND id_sewa <> @id_sewa_1
ORDER BY id_sewa ASC
LIMIT 1;


-- =====================================================
-- 5. LIHAT DATA YANG DIPAKAI UNTUK PENGUJIAN
-- =====================================================
SELECT
    @kode_test AS kode_test,
    @id_pelanggan AS id_pelanggan_dipakai,
    @id_sewa_1 AS id_sewa_transaksi_1,
    @id_kendaraan_1 AS id_kendaraan_transaksi_1,
    @id_sewa_2 AS id_sewa_transaksi_2,
    @id_kendaraan_2 AS id_kendaraan_transaksi_2;


-- =====================================================
-- 6. KONDISI AWAL PELANGGAN DAN TRANSAKSI SEBELUM TRIGGER
-- =====================================================
SELECT
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.nik,
    p.status_akun AS status_akun_sebelum,
    COUNT(ks.id_sewa) AS total_transaksi_pelanggan
FROM pelanggan p
LEFT JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
WHERE p.id_pelanggan = @id_pelanggan
GROUP BY
    p.id_pelanggan,
    nama_pelanggan,
    p.nik,
    p.status_akun;


SELECT
    ks.id_sewa,
    ks.status_sewa AS status_sewa_sebelum,
    COUNT(pg.id_pelanggaran) AS total_pelanggaran_per_transaksi_sebelum
FROM kontrak_sewa ks
LEFT JOIN pelanggaran_geofence pg ON ks.id_sewa = pg.id_sewa
WHERE ks.id_sewa IN (@id_sewa_1, @id_sewa_2)
GROUP BY
    ks.id_sewa,
    ks.status_sewa;


-- =====================================================
-- 7. INSERT 1 PELANGGARAN GEOFENCE BERAT
-- Jarak 55.75 km menghasilkan skor risiko tinggi
-- =====================================================
INSERT INTO pelanggaran_geofence (
    id_kendaraan,
    id_sewa,
    waktu_pelanggaran,
    lokasi_valid_terakhir,
    lokasi_pelanggaran,
    jarak_pelanggaran_km,
    status_penanganan
)
VALUES (
    @id_kendaraan_1,
    @id_sewa_1,
    NOW(),
    'Surabaya Pusat',
    CONCAT(@kode_test, ' - Pelanggaran Berat Transaksi 1'),
    55.75,
    'Belum Diproses'
);

SET @id_pelanggaran_1 = LAST_INSERT_ID();


-- =====================================================
-- 8. BUKTI DATA MASUK KE pelanggaran_geofence
-- =====================================================
SELECT
    id_pelanggaran,
    id_kendaraan,
    id_sewa,
    waktu_pelanggaran,
    lokasi_valid_terakhir,
    lokasi_pelanggaran,
    jarak_pelanggaran_km,
    status_penanganan
FROM pelanggaran_geofence
WHERE id_pelanggaran = @id_pelanggaran_1;


-- =====================================================
-- 9. BUKTI TRIGGER OTOMATIS INSERT KE log_anomali
-- Tidak pakai LIKE agar tidak error collation
-- =====================================================
SELECT
    id_anomali,
    id_sewa,
    jenis_anomali,
    waktu_log,
    deskripsi,
    skor_risiko,
    status_tindak_lanjut
FROM log_anomali
WHERE id_anomali > @min_anomali_id
  AND id_sewa = @id_sewa_1
ORDER BY id_anomali DESC
LIMIT 1;


-- =====================================================
-- 10. BUKTI TRIGGER UPDATE STATUS SEWA DAN STATUS AKUN
-- Karena jarak 55.75 km, skor risiko tinggi
-- Status sewa menjadi Macet-Hukum
-- Status akun menjadi Ditangguhkan
-- =====================================================
SELECT
    ks.id_sewa,
    ks.status_sewa AS status_sewa_setelah_trigger,
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun AS status_akun_setelah_trigger
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
WHERE ks.id_sewa = @id_sewa_1;


-- =====================================================
-- 11. TAMBAH PELANGGARAN LAGI UNTUK UJI REKAP PER PELANGGAN
-- Total pelanggaran baru akan menjadi 5:
-- Transaksi 1 = 3 pelanggaran
-- Transaksi 2 = 2 pelanggaran
-- =====================================================
INSERT INTO pelanggaran_geofence (
    id_kendaraan,
    id_sewa,
    waktu_pelanggaran,
    lokasi_valid_terakhir,
    lokasi_pelanggaran,
    jarak_pelanggaran_km,
    status_penanganan
)
VALUES
(
    @id_kendaraan_1,
    @id_sewa_1,
    DATE_ADD(NOW(), INTERVAL 1 MINUTE),
    'Surabaya Pusat',
    CONCAT(@kode_test, ' - Pelanggaran 2 Transaksi 1'),
    12.50,
    'Diperingatkan'
),
(
    @id_kendaraan_1,
    @id_sewa_1,
    DATE_ADD(NOW(), INTERVAL 2 MINUTE),
    'Surabaya Pusat',
    CONCAT(@kode_test, ' - Pelanggaran 3 Transaksi 1'),
    15.25,
    'Diperingatkan'
),
(
    @id_kendaraan_2,
    @id_sewa_2,
    DATE_ADD(NOW(), INTERVAL 3 MINUTE),
    'Surabaya Pusat',
    CONCAT(@kode_test, ' - Pelanggaran 1 Transaksi 2'),
    11.75,
    'Belum Diproses'
),
(
    @id_kendaraan_2,
    @id_sewa_2,
    DATE_ADD(NOW(), INTERVAL 4 MINUTE),
    'Surabaya Pusat',
    CONCAT(@kode_test, ' - Pelanggaran 2 Transaksi 2'),
    13.80,
    'Diperingatkan'
);


-- =====================================================
-- 12. BUKTI PELANGGARAN TERCATAT PER TRANSAKSI
-- Hanya menghitung data baru dari pengujian ini
-- =====================================================
SELECT
    ks.id_sewa,
    ks.status_sewa,
    COUNT(pg.id_pelanggaran) AS total_pelanggaran_baru_per_transaksi
FROM kontrak_sewa ks
LEFT JOIN pelanggaran_geofence pg 
    ON ks.id_sewa = pg.id_sewa
   AND pg.id_pelanggaran > @min_pelanggaran_id
WHERE ks.id_sewa IN (@id_sewa_1, @id_sewa_2)
GROUP BY
    ks.id_sewa,
    ks.status_sewa;


-- =====================================================
-- 13. BUKTI PELANGGARAN TERCATAT PER PELANGGAN
-- Total pelanggaran pelanggan dari seluruh transaksi = 5
-- =====================================================
SELECT
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.nik,
    p.status_akun,
    COUNT(DISTINCT ks.id_sewa) AS total_transaksi_pelanggan,
    COUNT(pg.id_pelanggaran) AS total_pelanggaran_baru_pelanggan_semua_transaksi
FROM pelanggan p
JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
LEFT JOIN pelanggaran_geofence pg 
    ON ks.id_sewa = pg.id_sewa
   AND pg.id_pelanggaran > @min_pelanggaran_id
WHERE p.id_pelanggan = @id_pelanggan
GROUP BY
    p.id_pelanggan,
    nama_pelanggan,
    p.nik,
    p.status_akun;


-- =====================================================
-- 14. BUKTI PELANGGAN MASUK KE daftar_hitam
-- Jika total pelanggaran pelanggan sudah mencapai batas blacklist
-- Tidak pakai pencarian teks, cukup pakai id_daftar_hitam
-- =====================================================
SELECT
    id_daftar_hitam,
    nik,
    nama_lengkap,
    jenis_pelanggaran,
    tanggal_kejadian,
    id_rental_pelapor,
    status_verifikasi
FROM daftar_hitam
WHERE id_daftar_hitam > @min_daftar_hitam_id
ORDER BY id_daftar_hitam DESC;


-- =====================================================
-- 15. BUKTI LOG ANOMALI YANG DIBUAT TRIGGER
-- Tidak pakai LIKE agar tidak error collation
-- =====================================================
SELECT
    id_anomali,
    id_sewa,
    jenis_anomali,
    waktu_log,
    deskripsi,
    skor_risiko,
    status_tindak_lanjut
FROM log_anomali
WHERE id_anomali > @min_anomali_id
  AND id_sewa IN (@id_sewa_1, @id_sewa_2)
ORDER BY id_anomali DESC;


-- =====================================================
-- 16. CEK STATUS AKHIR PELANGGAN DAN DUA TRANSAKSI
-- Setelah total pelanggaran pelanggan mencapai 5,
-- akun pelanggan seharusnya menjadi Diblokir
-- =====================================================
SELECT
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.nik,
    p.status_akun AS status_akun_akhir
FROM pelanggan p
WHERE p.id_pelanggan = @id_pelanggan;


SELECT
    ks.id_sewa,
    ks.status_sewa AS status_sewa_akhir
FROM kontrak_sewa ks
WHERE ks.id_sewa IN (@id_sewa_1, @id_sewa_2)
ORDER BY ks.id_sewa;


-- =====================================================
-- 17. KEMBALIKAN DATA TEST AGAR DATABASE TETAP BERSIH
-- Kalau ingin data test disimpan, ganti ROLLBACK menjadi COMMIT
-- =====================================================
ROLLBACK;

-- COMMIT;

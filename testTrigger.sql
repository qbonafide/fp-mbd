USE fp_rental_kendaraan;

-- =====================================================
-- 1. CEK TRIGGER SUDAH TERPASANG
-- =====================================================
SHOW TRIGGERS LIKE 'pelanggaran_geofence';


-- =====================================================
-- 2. AMBIL DATA KONTRAK YANG BISA DIPAKAI UNTUK TEST
-- =====================================================
SET @id_sewa = (
    SELECT ks.id_sewa
    FROM kontrak_sewa ks
    JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
    WHERE ks.status_sewa IN ('Aktif', 'Terlambat', 'Dipesan')
      AND p.status_akun = 'Aktif'
    LIMIT 1
);

SET @id_kendaraan = (
    SELECT id_kendaraan
    FROM kontrak_sewa
    WHERE id_sewa = @id_sewa
    LIMIT 1
);

SET @id_pelanggan = (
    SELECT id_pelanggan
    FROM kontrak_sewa
    WHERE id_sewa = @id_sewa
    LIMIT 1
);

SET @kode_test = CONCAT('TEST_TRIGGER_GEOFENCE_', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'));

SELECT 
    @id_sewa AS id_sewa_dipakai,
    @id_kendaraan AS id_kendaraan_dipakai,
    @id_pelanggan AS id_pelanggan_dipakai,
    @kode_test AS kode_test;


-- =====================================================
-- 3. LIHAT STATUS SEBELUM TRIGGER DIJALANKAN
-- =====================================================
SELECT 
    ks.id_sewa,
    ks.status_sewa AS status_sewa_sebelum,
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun AS status_akun_sebelum
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
WHERE ks.id_sewa = @id_sewa;


-- =====================================================
-- 4. MULAI TRANSAKSI TEST
-- Data test bisa dibatalkan dengan ROLLBACK
-- =====================================================
START TRANSACTION;

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
    @id_kendaraan,
    @id_sewa,
    NOW(),
    'Surabaya Pusat',
    @kode_test,
    55.75,
    'Belum Diproses'
);

SET @id_pelanggaran = LAST_INSERT_ID();


-- =====================================================
-- 5. BUKTI DATA MASUK KE pelanggaran_geofence
-- =====================================================
SELECT *
FROM pelanggaran_geofence
WHERE id_pelanggaran = @id_pelanggaran;


-- =====================================================
-- 6. BUKTI TRIGGER OTOMATIS INSERT KE log_anomali
-- =====================================================
SELECT *
FROM log_anomali
WHERE id_sewa = @id_sewa
  AND deskripsi LIKE CONCAT('%', @kode_test, '%')
ORDER BY id_anomali DESC
LIMIT 1;


-- =====================================================
-- 7. BUKTI TRIGGER UPDATE STATUS KONTRAK DAN PELANGGAN
-- =====================================================
SELECT 
    ks.id_sewa,
    ks.status_sewa AS status_sewa_setelah_trigger,
    p.id_pelanggan,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun AS status_akun_setelah_trigger
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
WHERE ks.id_sewa = @id_sewa;


-- =====================================================
-- 8. KEMBALIKAN DATA TEST AGAR DATABASE TETAP BERSIH
-- Jalankan setelah screenshot selesai.
-- Kalau ingin data test disimpan, ganti ROLLBACK menjadi COMMIT.
-- =====================================================
ROLLBACK;
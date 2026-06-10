USE fp_rental_kendaraan;

-- =====================================================
-- PEKERJAAN 7 - DATABASE TRANSACTION
-- 10 Skenario: COMMIT dan ROLLBACK
-- Sistem Rental Kendaraan Anti-Fraud
-- =====================================================


-- =====================================================
-- TRANSACTION 1 - COMMIT
-- Skenario: Penyewaan baru valid
-- Kondisi: pelanggan aktif, tidak blacklist, kendaraan tersedia
-- =====================================================

START TRANSACTION;

SELECT p.id_pelanggan
INTO @t1_id_pelanggan
FROM pelanggan p
LEFT JOIN daftar_hitam dh
    ON p.nik = dh.nik
    AND dh.status_verifikasi = 'Terverifikasi'
WHERE p.status_akun = 'Aktif'
  AND dh.nik IS NULL
LIMIT 1;

SELECT k.id_kendaraan
INTO @t1_id_kendaraan
FROM kendaraan k
WHERE k.status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

SELECT kk.tarif_harian
INTO @t1_tarif_harian
FROM kendaraan k
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE k.id_kendaraan = @t1_id_kendaraan;

SET @t1_durasi_hari = 2;
SET @t1_total_harga = @t1_tarif_harian * @t1_durasi_hari;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t1_id_pelanggan,
    @t1_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL @t1_durasi_hari DAY),
    NULL,
    @t1_total_harga,
    'Aktif'
);

SET @t1_id_sewa = LAST_INSERT_ID();

INSERT INTO dokumen_jaminan (
    id_sewa,
    jenis_dokumen,
    nomor_dokumen,
    kondisi_penyimpanan,
    lokasi_loker,
    waktu_serah_terima
)
VALUES
(@t1_id_sewa, 'KTP', CONCAT('KTP-COMMIT-1-', @t1_id_sewa), 'Disimpan fisik dalam map jaminan', CONCAT('Loker-T1-', @t1_id_sewa), NOW()),
(@t1_id_sewa, 'SIM', CONCAT('SIM-COMMIT-1-', @t1_id_sewa), 'Disimpan fisik dalam map jaminan', CONCAT('Loker-T1-', @t1_id_sewa), NOW());

INSERT INTO konfigurasi_geofence (
    id_sewa,
    pusat_latitude,
    pusat_longitude,
    radius_km,
    batas_poligon,
    status_aktif
)
VALUES (
    @t1_id_sewa,
    -7.25750000,
    112.75210000,
    25.00,
    NULL,
    1
);

INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
VALUES (
    @t1_id_sewa,
    NOW(),
    @t1_total_harga,
    'Transfer Bank',
    'Lunas'
);

UPDATE kendaraan
SET status_kendaraan = 'Sedang Disewa'
WHERE id_kendaraan = @t1_id_kendaraan;

COMMIT;

SELECT 'TRANSACTION 1 COMMIT - Penyewaan baru valid berhasil disimpan' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t1_id_sewa;
SELECT * FROM dokumen_jaminan WHERE id_sewa = @t1_id_sewa;
SELECT * FROM konfigurasi_geofence WHERE id_sewa = @t1_id_sewa;
SELECT * FROM pembayaran WHERE id_sewa = @t1_id_sewa;


-- =====================================================
-- TRANSACTION 2 - COMMIT
-- Skenario: Pengembalian kendaraan tepat waktu dan kondisi baik
-- Kondisi: kendaraan kembali tanpa denda dan tanpa kerusakan
-- =====================================================

START TRANSACTION;

SELECT 
    ks.id_sewa,
    ks.id_kendaraan
INTO
    @t2_id_sewa,
    @t2_id_kendaraan
FROM kontrak_sewa ks
WHERE ks.status_sewa = 'Aktif'
LIMIT 1
FOR UPDATE;

SET @t2_waktu_kembali = NOW();

INSERT INTO inspeksi_kendaraan (
    id_sewa,
    tipe_inspeksi,
    waktu_inspeksi,
    url_foto_1,
    url_foto_2,
    deskripsi_kondisi,
    id_petugas,
    hash_dokumen
)
VALUES (
    @t2_id_sewa,
    'Pasca-Sewa',
    @t2_waktu_kembali,
    CONCAT('foto_t2_pasca_', @t2_id_sewa, '_1.jpg'),
    CONCAT('foto_t2_pasca_', @t2_id_sewa, '_2.jpg'),
    'Kendaraan kembali dalam kondisi baik dan tidak ditemukan kerusakan.',
    102,
    SHA2(CONCAT('T2-PASCA-SEWA-', @t2_id_sewa, @t2_waktu_kembali), 256)
);

UPDATE kontrak_sewa
SET 
    tanggal_kembali_aktual = @t2_waktu_kembali,
    status_sewa = 'Selesai'
WHERE id_sewa = @t2_id_sewa;

UPDATE kendaraan
SET status_kendaraan = 'Tersedia'
WHERE id_kendaraan = @t2_id_kendaraan;

COMMIT;

SELECT 'TRANSACTION 2 COMMIT - Pengembalian tepat waktu berhasil disimpan' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t2_id_sewa;
SELECT * FROM inspeksi_kendaraan WHERE id_sewa = @t2_id_sewa ORDER BY id_inspeksi DESC LIMIT 1;
SELECT * FROM kendaraan WHERE id_kendaraan = @t2_id_kendaraan;


-- =====================================================
-- TRANSACTION 3 - COMMIT
-- Skenario: Pengembalian terlambat dan denda dibayar lunas
-- Kondisi: telat bayar/terlambat, tetapi denda berhasil dicatat
-- =====================================================

START TRANSACTION;

SELECT 
    ks.id_sewa,
    ks.id_kendaraan,
    kk.denda_keterlambatan_per_jam
INTO
    @t3_id_sewa,
    @t3_id_kendaraan,
    @t3_denda_per_jam
FROM kontrak_sewa ks
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE ks.status_sewa IN ('Aktif', 'Terlambat')
LIMIT 1
FOR UPDATE;

SET @t3_jam_terlambat = 12;
SET @t3_total_denda = @t3_jam_terlambat * @t3_denda_per_jam;

INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
VALUES (
    @t3_id_sewa,
    NOW(),
    @t3_total_denda,
    'QRIS',
    'Lunas'
);

UPDATE kontrak_sewa
SET
    tanggal_kembali_aktual = NOW(),
    status_sewa = 'Selesai'
WHERE id_sewa = @t3_id_sewa;

UPDATE kendaraan
SET status_kendaraan = 'Tersedia'
WHERE id_kendaraan = @t3_id_kendaraan;

INSERT INTO log_anomali (
    id_sewa,
    jenis_anomali,
    waktu_log,
    deskripsi,
    skor_risiko,
    status_tindak_lanjut
)
VALUES (
    @t3_id_sewa,
    'Keterlambatan Pengembalian',
    NOW(),
    CONCAT('Kendaraan terlambat dikembalikan selama ', @t3_jam_terlambat, ' jam. Denda telah dibayar lunas.'),
    50,
    'Selesai'
);

COMMIT;

SELECT 'TRANSACTION 3 COMMIT - Pengembalian terlambat dengan denda lunas berhasil disimpan' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t3_id_sewa;
SELECT * FROM pembayaran WHERE id_sewa = @t3_id_sewa ORDER BY id_pembayaran DESC LIMIT 1;
SELECT * FROM log_anomali WHERE id_sewa = @t3_id_sewa ORDER BY id_anomali DESC LIMIT 1;


-- =====================================================
-- TRANSACTION 4 - COMMIT
-- Skenario: Pengembalian kendaraan dengan kerusakan ringan
-- Kondisi: kendaraan lecet, status kendaraan menjadi Rusak, log anomali dicatat
-- =====================================================

START TRANSACTION;

SELECT 
    ks.id_sewa,
    ks.id_kendaraan
INTO
    @t4_id_sewa,
    @t4_id_kendaraan
FROM kontrak_sewa ks
WHERE ks.status_sewa IN ('Aktif', 'Terlambat')
LIMIT 1
FOR UPDATE;

SET @t4_kondisi = 'Ditemukan lecet pada bumper belakang dan baret pada pintu kiri.';

INSERT INTO inspeksi_kendaraan (
    id_sewa,
    tipe_inspeksi,
    waktu_inspeksi,
    url_foto_1,
    url_foto_2,
    deskripsi_kondisi,
    id_petugas,
    hash_dokumen
)
VALUES (
    @t4_id_sewa,
    'Pasca-Sewa',
    NOW(),
    CONCAT('foto_t4_rusak_', @t4_id_sewa, '_1.jpg'),
    CONCAT('foto_t4_rusak_', @t4_id_sewa, '_2.jpg'),
    @t4_kondisi,
    103,
    SHA2(CONCAT('T4-RUSAK-', @t4_id_sewa, NOW()), 256)
);

UPDATE kendaraan
SET status_kendaraan = 'Rusak'
WHERE id_kendaraan = @t4_id_kendaraan;

INSERT INTO log_anomali (
    id_sewa,
    jenis_anomali,
    waktu_log,
    deskripsi,
    skor_risiko,
    status_tindak_lanjut
)
VALUES (
    @t4_id_sewa,
    'Kerusakan Kendaraan',
    NOW(),
    CONCAT('Kerusakan pasca-sewa terdeteksi: ', @t4_kondisi),
    70,
    'Perlu Ditinjau'
);

COMMIT;

SELECT 'TRANSACTION 4 COMMIT - Kerusakan kendaraan berhasil dicatat' AS hasil;
SELECT * FROM inspeksi_kendaraan WHERE id_sewa = @t4_id_sewa ORDER BY id_inspeksi DESC LIMIT 1;
SELECT * FROM kendaraan WHERE id_kendaraan = @t4_id_kendaraan;
SELECT * FROM log_anomali WHERE id_sewa = @t4_id_sewa ORDER BY id_anomali DESC LIMIT 1;


-- =====================================================
-- TRANSACTION 5 - COMMIT
-- Skenario: Pelanggaran geofence berat
-- Kondisi: kendaraan keluar radius jauh, status sewa menjadi Macet-Hukum
-- Catatan: jika trigger sudah dibuat, insert ini juga akan memicu trigger
-- =====================================================

START TRANSACTION;

SELECT 
    ks.id_sewa,
    ks.id_kendaraan,
    ks.id_pelanggan
INTO
    @t5_id_sewa,
    @t5_id_kendaraan,
    @t5_id_pelanggan
FROM kontrak_sewa ks
WHERE ks.status_sewa IN ('Aktif', 'Terlambat')
LIMIT 1
FOR UPDATE;

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
    @t5_id_kendaraan,
    @t5_id_sewa,
    NOW(),
    'Surabaya Pusat',
    'Luar Kota - Area Risiko Tinggi',
    60.50,
    'Diperingatkan'
);

SET @t5_id_pelanggaran = LAST_INSERT_ID();

UPDATE kontrak_sewa
SET status_sewa = 'Macet-Hukum'
WHERE id_sewa = @t5_id_sewa;

UPDATE pelanggan
SET status_akun = 'Ditangguhkan'
WHERE id_pelanggan = @t5_id_pelanggan;

COMMIT;

SELECT 'TRANSACTION 5 COMMIT - Pelanggaran geofence berat berhasil diproses' AS hasil;
SELECT * FROM pelanggaran_geofence WHERE id_pelanggaran = @t5_id_pelanggaran;
SELECT 
    ks.id_sewa,
    ks.status_sewa,
    p.id_pelanggan,
    p.status_akun
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
WHERE ks.id_sewa = @t5_id_sewa;


-- =====================================================
-- TRANSACTION 6 - ROLLBACK
-- Skenario: Pelanggan blacklist mencoba menyewa kendaraan
-- Kondisi: pelanggan masuk daftar_hitam terverifikasi, maka transaksi dibatalkan
-- =====================================================

START TRANSACTION;

SELECT p.id_pelanggan
INTO @t6_id_pelanggan
FROM pelanggan p
JOIN daftar_hitam dh ON p.nik = dh.nik
WHERE dh.status_verifikasi = 'Terverifikasi'
LIMIT 1;

SELECT id_kendaraan
INTO @t6_id_kendaraan
FROM kendaraan
WHERE status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t6_id_pelanggan,
    @t6_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 1 DAY),
    NULL,
    300000,
    'Dipesan'
);

SET @t6_id_sewa = LAST_INSERT_ID();

SELECT 'TRANSACTION 6 ROLLBACK - Pelanggan terdaftar blacklist, transaksi dibatalkan' AS alasan_rollback;

ROLLBACK;

SELECT 'CEK TRANSACTION 6 - Data kontrak tidak tersimpan karena ROLLBACK' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t6_id_sewa;


-- =====================================================
-- TRANSACTION 7 - ROLLBACK
-- Skenario: Kendaraan tidak tersedia dipaksa disewa
-- Kondisi: kendaraan bukan Tersedia, maka transaksi dibatalkan
-- =====================================================

START TRANSACTION;

SELECT id_pelanggan
INTO @t7_id_pelanggan
FROM pelanggan
WHERE status_akun = 'Aktif'
LIMIT 1;

SELECT id_kendaraan
INTO @t7_id_kendaraan
FROM kendaraan
WHERE status_kendaraan <> 'Tersedia'
LIMIT 1
FOR UPDATE;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t7_id_pelanggan,
    @t7_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 2 DAY),
    NULL,
    400000,
    'Dipesan'
);

SET @t7_id_sewa = LAST_INSERT_ID();

SELECT 'TRANSACTION 7 ROLLBACK - Kendaraan tidak tersedia, transaksi dibatalkan' AS alasan_rollback;

ROLLBACK;

SELECT 'CEK TRANSACTION 7 - Data kontrak tidak tersimpan karena ROLLBACK' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t7_id_sewa;


-- =====================================================
-- TRANSACTION 8 - ROLLBACK
-- Skenario: Dokumen jaminan tidak lengkap
-- Kondisi: hanya KTP, tidak ada SIM, maka transaksi dibatalkan
-- =====================================================

START TRANSACTION;

SELECT id_pelanggan
INTO @t8_id_pelanggan
FROM pelanggan
WHERE status_akun = 'Aktif'
LIMIT 1;

SELECT id_kendaraan
INTO @t8_id_kendaraan
FROM kendaraan
WHERE status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t8_id_pelanggan,
    @t8_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 2 DAY),
    NULL,
    450000,
    'Dipesan'
);

SET @t8_id_sewa = LAST_INSERT_ID();

INSERT INTO dokumen_jaminan (
    id_sewa,
    jenis_dokumen,
    nomor_dokumen,
    kondisi_penyimpanan,
    lokasi_loker,
    waktu_serah_terima
)
VALUES (
    @t8_id_sewa,
    'KTP',
    CONCAT('KTP-ROLLBACK-8-', @t8_id_sewa),
    'Dokumen fisik diterima',
    CONCAT('Loker-T8-', @t8_id_sewa),
    NOW()
);

SELECT COUNT(*) 
INTO @t8_jumlah_dokumen
FROM dokumen_jaminan
WHERE id_sewa = @t8_id_sewa;

SELECT 'TRANSACTION 8 ROLLBACK - Dokumen jaminan tidak lengkap, transaksi dibatalkan' AS alasan_rollback,
       @t8_jumlah_dokumen AS jumlah_dokumen_yang_masuk;

ROLLBACK;

SELECT 'CEK TRANSACTION 8 - Kontrak dan dokumen tidak tersimpan karena ROLLBACK' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t8_id_sewa;
SELECT * FROM dokumen_jaminan WHERE id_sewa = @t8_id_sewa;


-- =====================================================
-- TRANSACTION 9 - ROLLBACK
-- Skenario: Radius geofence terlalu besar
-- Kondisi: radius 300 km dianggap tidak aman, maka transaksi dibatalkan
-- =====================================================

START TRANSACTION;

SELECT id_pelanggan
INTO @t9_id_pelanggan
FROM pelanggan
WHERE status_akun = 'Aktif'
LIMIT 1;

SELECT id_kendaraan
INTO @t9_id_kendaraan
FROM kendaraan
WHERE status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t9_id_pelanggan,
    @t9_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 2 DAY),
    NULL,
    500000,
    'Dipesan'
);

SET @t9_id_sewa = LAST_INSERT_ID();

INSERT INTO konfigurasi_geofence (
    id_sewa,
    pusat_latitude,
    pusat_longitude,
    radius_km,
    batas_poligon,
    status_aktif
)
VALUES (
    @t9_id_sewa,
    -7.25750000,
    112.75210000,
    300.00,
    NULL,
    1
);

SELECT 'TRANSACTION 9 ROLLBACK - Radius geofence terlalu besar, transaksi dibatalkan' AS alasan_rollback;

ROLLBACK;

SELECT 'CEK TRANSACTION 9 - Kontrak dan geofence tidak tersimpan karena ROLLBACK' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t9_id_sewa;
SELECT * FROM konfigurasi_geofence WHERE id_sewa = @t9_id_sewa;


-- =====================================================
-- TRANSACTION 10 - ROLLBACK
-- Skenario: Pembayaran awal masih Pending
-- Kondisi: pembayaran belum lunas, kontrak tidak boleh diaktifkan
-- =====================================================

START TRANSACTION;

SELECT id_pelanggan
INTO @t10_id_pelanggan
FROM pelanggan
WHERE status_akun = 'Aktif'
LIMIT 1;

SELECT id_kendaraan
INTO @t10_id_kendaraan
FROM kendaraan
WHERE status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @t10_id_pelanggan,
    @t10_id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL 2 DAY),
    NULL,
    550000,
    'Dipesan'
);

SET @t10_id_sewa = LAST_INSERT_ID();

INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
VALUES (
    @t10_id_sewa,
    NOW(),
    550000,
    'E-Wallet',
    'Pending'
);

SELECT 'TRANSACTION 10 ROLLBACK - Pembayaran masih Pending, transaksi dibatalkan' AS alasan_rollback;

ROLLBACK;

SELECT 'CEK TRANSACTION 10 - Kontrak dan pembayaran tidak tersimpan karena ROLLBACK' AS hasil;
SELECT * FROM kontrak_sewa WHERE id_sewa = @t10_id_sewa;
SELECT * FROM pembayaran WHERE id_sewa = @t10_id_sewa;
USE fp_rental_kendaraan;

-- =====================================================
-- CLEAN UP DATA
-- =====================================================

UPDATE pelanggan p
JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
SET p.status_akun = 'Aktif'
WHERE ks.id_sewa IN (9000001, 9000002);

UPDATE kendaraan k
JOIN kontrak_sewa ks ON k.id_kendaraan = ks.id_kendaraan
SET k.status_kendaraan = 'Tersedia'
WHERE ks.id_sewa IN (9000001, 9000002);

DELETE FROM pembayaran
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM inspeksi_kendaraan
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM log_anomali
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM pelanggaran_geofence
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM dokumen_jaminan
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM konfigurasi_geofence
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM kontrak_sewa
WHERE id_sewa IN (9000001, 9000002);

DELETE FROM daftar_hitam
WHERE id_daftar_hitam = 9000001;


-- =====================================================
-- DATA PENDUKUNG
-- =====================================================

INSERT INTO komunitas_rental (
    id_rental,
    nama_rental,
    kota,
    kontak,
    api_key,
    status_keanggotaan,
    tanggal_bergabung
)
SELECT
    9000001,
    'Rental Pelapor Transaction',
    'Surabaya',
    '081234567890',
    'API-TRANSACTION-9000001',
    'Aktif',
    '2026-07-01'
WHERE NOT EXISTS (
    SELECT 1
    FROM komunitas_rental
    WHERE id_rental = 9000001
);


-- =====================================================
-- Sceneraio 1 - COMMIT
-- SKENARIO: PENYEWAAN BARU DAN VALID
--
-- Dalam satu transaksi ini dilakukan:
-- 1. Mengecek pelanggan aktif
-- 2. Mengecek pelanggan tidak masuk daftar hitam
-- 3. Mengecek kendaraan tersedia
-- 4. Mengecek jadwal kendaraan tidak bertabrakan
-- 5. Menyimpan kontrak sewa
-- 6. Menyimpan dokumen jaminan lengkap
-- 7. Menyimpan konfigurasi geofence aman
-- 8. Menyimpan pembayaran lunas
-- 9. Menyimpan inspeksi pra-sewa
-- 10. Mengubah status kendaraan menjadi Sedang Disewa
-- =====================================================

START TRANSACTION;

-- BEFORE: pengecekan awal
SELECT
    'BEFORE TRANSACTION 1' AS tahap,
    p.id_pelanggan,
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun,
    k.id_kendaraan,
    k.plat_nomor,
    k.status_kendaraan,
    'Aman: pelanggan aktif, tidak blacklist, kendaraan tersedia, jadwal tidak tabrakan' AS keterangan
FROM pelanggan p
CROSS JOIN kendaraan k
WHERE p.status_akun = 'Aktif'
  AND k.status_kendaraan = 'Tersedia'
  AND NOT EXISTS (
      SELECT 1
      FROM daftar_hitam dh
      WHERE dh.nik = p.nik
        AND dh.status_verifikasi = 'Terverifikasi'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM kontrak_sewa ks
      WHERE ks.id_kendaraan = k.id_kendaraan
        AND ks.status_sewa IN ('Dipesan', 'Aktif', 'Terlambat', 'Proses Hukum')
        AND '2026-07-10 09:00:00' < ks.tanggal_kembali_rencana
        AND '2026-07-13 09:00:00' > ks.tanggal_ambil
  )
LIMIT 1;

-- Membuat kontrak sewa valid
INSERT INTO kontrak_sewa (
    id_sewa,
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
SELECT
    9000001,
    p.id_pelanggan,
    k.id_kendaraan,
    '2026-07-10 09:00:00',
    '2026-07-13 09:00:00',
    NULL,
    kk.tarif_harian * 3,
    'Aktif'
FROM pelanggan p
CROSS JOIN kendaraan k
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE p.status_akun = 'Aktif'
  AND k.status_kendaraan = 'Tersedia'
  AND NOT EXISTS (
      SELECT 1
      FROM daftar_hitam dh
      WHERE dh.nik = p.nik
        AND dh.status_verifikasi = 'Terverifikasi'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM kontrak_sewa ks
      WHERE ks.id_kendaraan = k.id_kendaraan
        AND ks.status_sewa IN ('Dipesan', 'Aktif', 'Terlambat', 'Proses Hukum')
        AND '2026-07-10 09:00:00' < ks.tanggal_kembali_rencana
        AND '2026-07-13 09:00:00' > ks.tanggal_ambil
  )
LIMIT 1;

-- Menyimpan dokumen jaminan lengkap
INSERT INTO dokumen_jaminan (
    id_sewa,
    jenis_dokumen,
    nomor_dokumen,
    kondisi_penyimpanan,
    lokasi_loker,
    waktu_serah_terima
)
VALUES
(
    9000001,
    'KTP',
    'KTP-TRX-9000001',
    'Dokumen tersimpan dengan baik',
    'Loker-9000001',
    NOW()
),
(
    9000001,
    'SIM',
    'SIM-TRX-9000001',
    'Dokumen tersimpan dengan baik',
    'Loker-9000001',
    NOW()
);

-- Menyimpan konfigurasi geofence aman
INSERT INTO konfigurasi_geofence (
    id_sewa,
    pusat_latitude,
    pusat_longitude,
    radius_km,
    status_aktif
)
VALUES (
    9000001,
    -7.25750000,
    112.75210000,
    25.00,
    1
);

-- Menyimpan pembayaran awal lunas
INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
SELECT
    9000001,
    NOW(),
    total_harga,
    'Transfer Bank',
    'Lunas'
FROM kontrak_sewa
WHERE id_sewa = 9000001;

-- Menyimpan inspeksi pra-sewa
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
    9000001,
    'Pra-Sewa',
    NOW(),
    'pra_sewa_9000001_1.jpg',
    'pra_sewa_9000001_2.jpg',
    'Kendaraan dalam kondisi baik sebelum disewakan.',
    1,
    SHA2('PRA-SEWA-9000001', 256)
);

-- Mengubah status kendaraan menjadi Sedang Disewa
UPDATE kendaraan
SET status_kendaraan = 'Sedang Disewa'
WHERE id_kendaraan = (
    SELECT id_kendaraan
    FROM kontrak_sewa
    WHERE id_sewa = 9000001
);

-- AFTER: pengecekan hasil sebelum COMMIT
SELECT
    'AFTER TRANSACTION 1 BEFORE COMMIT' AS tahap,
    ks.id_sewa,
    ks.status_sewa,
    k.status_kendaraan,
    COUNT(DISTINCT dj.id_dokumen) AS jumlah_dokumen,
    COUNT(DISTINCT pb.id_pembayaran) AS jumlah_pembayaran
FROM kontrak_sewa ks
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN dokumen_jaminan dj ON ks.id_sewa = dj.id_sewa
LEFT JOIN pembayaran pb ON ks.id_sewa = pb.id_sewa
WHERE ks.id_sewa = 9000001
GROUP BY
    ks.id_sewa,
    ks.status_sewa,
    k.status_kendaraan;

COMMIT;

SELECT 'TRANSACTION 1 COMMIT - Penyewaan valid berhasil disimpan' AS hasil;


-- =====================================================
-- Scenario 2 - ROLLBACK
-- SKENARIO: PENYEWAAN DIBATALKAN KARENA TIDAK AMAN
--
-- Dalam satu transaksi besar ini terdapat beberapa masalah:
-- 1. Pelanggan diblokir dan masuk daftar hitam
-- 2. Jadwal kendaraan bertabrakan dengan sewa aktif
-- 3. Dokumen jaminan tidak lengkap
-- 4. Radius geofence terlalu besar
-- 5. Pembayaran masih pending
--
-- Karena tidak valid, seluruh proses dibatalkan dengan ROLLBACK
-- =====================================================

START TRANSACTION;

-- Simulasi pelanggan masuk daftar hitam
INSERT INTO daftar_hitam (
    id_daftar_hitam,
    nik,
    nama_lengkap,
    url_foto_wajah,
    jenis_pelanggaran,
    tanggal_kejadian,
    id_rental_pelapor,
    status_verifikasi
)
SELECT
    9000001,
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang),
    NULL,
    'Riwayat Penipuan Rental',
    '2026-07-11',
    9000001,
    'Terverifikasi'
FROM pelanggan p
JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
WHERE ks.id_sewa = 9000001;

-- Simulasi akun pelanggan diblokir
UPDATE pelanggan
SET status_akun = 'Diblokir'
WHERE id_pelanggan = (
    SELECT id_pelanggan
    FROM kontrak_sewa
    WHERE id_sewa = 9000001
);

-- BEFORE: pengecekan masalah
SELECT
    'BEFORE TRANSACTION 2' AS tahap,
    p.id_pelanggan,
    p.nik,
    p.status_akun,
    k.id_kendaraan,
    k.plat_nomor,
    (
        SELECT COUNT(*)
        FROM daftar_hitam dh
        WHERE dh.nik = p.nik
          AND dh.status_verifikasi = 'Terverifikasi'
    ) AS pelanggan_blacklist,
    (
        SELECT COUNT(*)
        FROM kontrak_sewa ks2
        WHERE ks2.id_kendaraan = k.id_kendaraan
          AND ks2.status_sewa IN ('Dipesan', 'Aktif', 'Terlambat', 'Proses Hukum')
          AND '2026-07-11 09:00:00' < ks2.tanggal_kembali_rencana
          AND '2026-07-14 09:00:00' > ks2.tanggal_ambil
    ) AS jadwal_tabrakan,
    'Tidak aman: pelanggan diblokir, jadwal tabrakan, dokumen tidak lengkap, geofence terlalu besar, pembayaran pending' AS keputusan
FROM pelanggan p
JOIN kontrak_sewa ks ON p.id_pelanggan = ks.id_pelanggan
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
WHERE ks.id_sewa = 9000001;

-- Data sengaja dimasukkan dulu untuk membuktikan ROLLBACK
INSERT INTO kontrak_sewa (
    id_sewa,
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
SELECT
    9000002,
    id_pelanggan,
    id_kendaraan,
    '2026-07-11 09:00:00',
    '2026-07-14 09:00:00',
    NULL,
    total_harga,
    'Dipesan'
FROM kontrak_sewa
WHERE id_sewa = 9000001;

-- Dokumen tidak lengkap: hanya KTP
INSERT INTO dokumen_jaminan (
    id_sewa,
    jenis_dokumen,
    nomor_dokumen,
    kondisi_penyimpanan,
    lokasi_loker,
    waktu_serah_terima
)
VALUES (
    9000002,
    'KTP',
    'KTP-TRX-9000002',
    'SIM belum diserahkan',
    'Loker-9000002',
    NOW()
);

-- Geofence tidak aman: radius terlalu besar
INSERT INTO konfigurasi_geofence (
    id_sewa,
    pusat_latitude,
    pusat_longitude,
    radius_km,
    status_aktif
)
VALUES (
    9000002,
    -7.25750000,
    112.75210000,
    300.00,
    1
);

-- Pembayaran masih pending
INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
SELECT
    9000002,
    NOW(),
    total_harga,
    'Transfer Bank',
    'Pending'
FROM kontrak_sewa
WHERE id_sewa = 9000002;

-- AFTER: data masuk sementara sebelum ROLLBACK
SELECT
    'AFTER INSERT BEFORE ROLLBACK' AS tahap,
    ks.id_sewa,
    ks.status_sewa,
    COUNT(DISTINCT dj.id_dokumen) AS jumlah_dokumen,
    COUNT(DISTINCT pb.id_pembayaran) AS jumlah_pembayaran
FROM kontrak_sewa ks
LEFT JOIN dokumen_jaminan dj ON ks.id_sewa = dj.id_sewa
LEFT JOIN pembayaran pb ON ks.id_sewa = pb.id_sewa
WHERE ks.id_sewa = 9000002
GROUP BY
    ks.id_sewa,
    ks.status_sewa;

ROLLBACK;

-- AFTER ROLLBACK: semua data gagal harus batal
SELECT
    'AFTER ROLLBACK TRANSACTION 2' AS tahap,
    (SELECT COUNT(*) FROM kontrak_sewa WHERE id_sewa = 9000002) AS kontrak_setelah_rollback,
    (SELECT COUNT(*) FROM dokumen_jaminan WHERE id_sewa = 9000002) AS dokumen_setelah_rollback,
    (SELECT COUNT(*) FROM pembayaran WHERE id_sewa = 9000002) AS pembayaran_setelah_rollback,
    (SELECT COUNT(*) FROM daftar_hitam WHERE id_daftar_hitam = 9000001) AS blacklist_setelah_rollback;

SELECT 'TRANSACTION 2 ROLLBACK - Penyewaan tidak aman berhasil dibatalkan' AS hasil;


-- =====================================================
-- Scenario 3 - COMMIT
-- SKENARIO: PENGEMBALIAN KENDARAAN DENGAN PEMERIKSAAN AKHIR
--
-- Dalam satu transaksi ini dilakukan:
-- 1. Mengecek kontrak masih aktif
-- 2. Menghitung keterlambatan
-- 3. Mencatat pembayaran denda
-- 4. Mencatat inspeksi pasca-sewa
-- 5. Membuat log anomali keterlambatan
-- 6. Mengubah status sewa menjadi Selesai
-- 7. Mengubah status kendaraan menjadi Tersedia
-- =====================================================

START TRANSACTION;

-- BEFORE: kondisi sebelum pengembalian
SELECT
    'BEFORE TRANSACTION 3' AS tahap,
    ks.id_sewa,
    ks.status_sewa,
    k.id_kendaraan,
    k.status_kendaraan,
    ks.tanggal_kembali_rencana,
    DATE_ADD(ks.tanggal_kembali_rencana, INTERVAL 5 HOUR) AS tanggal_kembali_aktual,
    5 AS jam_terlambat,
    kk.denda_keterlambatan_per_jam * 5 AS total_denda
FROM kontrak_sewa ks
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE ks.id_sewa = 9000001
  AND ks.status_sewa = 'Aktif'
FOR UPDATE;

-- Mencatat pembayaran denda
INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
SELECT
    ks.id_sewa,
    NOW(),
    kk.denda_keterlambatan_per_jam * 5,
    'QRIS',
    'Lunas'
FROM kontrak_sewa ks
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE ks.id_sewa = 9000001;

-- Mencatat inspeksi pasca-sewa
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
    9000001,
    'Pasca-Sewa',
    NOW(),
    'pasca_sewa_9000001_1.jpg',
    'pasca_sewa_9000001_2.jpg',
    'Kendaraan terlambat dikembalikan, tetapi kondisi kendaraan masih baik.',
    2,
    SHA2('PASCA-SEWA-9000001', 256)
);

-- Mencatat log anomali keterlambatan
INSERT INTO log_anomali (
    id_sewa,
    jenis_anomali,
    waktu_log,
    deskripsi,
    skor_risiko,
    status_tindak_lanjut
)
VALUES (
    9000001,
    'Keterlambatan Pengembalian',
    NOW(),
    'Kendaraan terlambat dikembalikan selama 5 jam dan denda telah dibayar lunas.',
    60,
    'Perlu Ditinjau'
);

-- Update status sewa
UPDATE kontrak_sewa
SET
    tanggal_kembali_aktual = DATE_ADD(tanggal_kembali_rencana, INTERVAL 5 HOUR),
    status_sewa = 'Selesai'
WHERE id_sewa = 9000001;

-- Update status kendaraan
UPDATE kendaraan
SET status_kendaraan = 'Tersedia'
WHERE id_kendaraan = (
    SELECT id_kendaraan
    FROM kontrak_sewa
    WHERE id_sewa = 9000001
);

-- AFTER: pengecekan hasil sebelum COMMIT
SELECT
    'AFTER TRANSACTION 3 BEFORE COMMIT' AS tahap,
    ks.id_sewa,
    ks.status_sewa,
    ks.tanggal_kembali_aktual,
    k.status_kendaraan,
    COUNT(DISTINCT pb.id_pembayaran) AS jumlah_pembayaran,
    COUNT(DISTINCT la.id_anomali) AS jumlah_log_anomali
FROM kontrak_sewa ks
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN pembayaran pb ON ks.id_sewa = pb.id_sewa
LEFT JOIN log_anomali la ON ks.id_sewa = la.id_sewa
WHERE ks.id_sewa = 9000001
GROUP BY
    ks.id_sewa,
    ks.status_sewa,
    ks.tanggal_kembali_aktual,
    k.status_kendaraan;

COMMIT;

SELECT 'TRANSACTION 3 COMMIT - Pengembalian kendaraan berhasil diproses' AS hasil;

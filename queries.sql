-- ============================================================
-- FILE: queries.sql
-- Pekerjaan 3: Query Kompleks & Optimasi Index
-- Peran: Data Analyst (Agil)
-- Database: fp_rental_kendaraan (MySQL/MariaDB)
-- ============================================================
-- ============================================================
--  FINAL PROJECT MBD A - 3 QUERY KOMPLEKS
--  Sistem Manajemen Rental Kendaraan Terintegrasi
-- ============================================================


-- ============================================================
--  QUERY 1: DETEKSI KENDARAAN OFF-GPS
--  Mendeteksi kendaraan aktif yang sinyal GPS-nya hilang
--  atau tidak update lebih dari 24 jam.
-- ============================================================

-- ---- SEBELUM OPTIMASI ----
-- Menggunakan nested subquery (2 level) untuk ambil log terbaru
SELECT
    k.plat_nomor,
    k.merk,
    k.model,
    ks.id_sewa,
    ks.status_sewa,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.no_telp,
    pl.waktu_log     AS terakhir_kirim_sinyal,
    pl.status_sinyal,
    TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) AS jam_sejak_sinyal_terakhir
FROM Kontrak_Sewa ks
-- Kontrak_Sewa: filter Kendaraan yang sedang disewa
JOIN Pelanggan p ON ks.id_pelanggan = p.id_pelanggan
-- Pelanggan: nama & nomor telpon penyewa
JOIN Kendaraan k ON ks.id_kendaraan = k.id_kendaraan
-- Kendaraan: identitas unit fisik Kendaraan
LEFT JOIN (
    -- Pelacakan_Lokasi: ambil log GPS terbaru per Kendaraan
    SELECT pl1.id_kendaraan, pl1.waktu_log, pl1.status_sinyal
    FROM Pelacakan_Lokasi pl1
    INNER JOIN (
        SELECT id_kendaraan, MAX(waktu_log) AS max_waktu
        FROM Pelacakan_Lokasi
        GROUP BY id_kendaraan
    ) pl2 ON pl1.id_kendaraan = pl2.id_kendaraan
         AND pl1.waktu_log    = pl2.max_waktu
) pl ON k.id_kendaraan = pl.id_kendaraan
WHERE ks.status_sewa IN ('aktif', 'terlambat')
  AND (
      pl.status_sinyal = 'hilang'
      OR pl.waktu_log IS NULL
      OR TIMESTAMPDIFF(HOUR, pl.waktu_log, NOW()) > 24
  )
LIMIT 20;


-- ---- SESUDAH OPTIMASI ----
-- [INDEX] Filter status sewa + join ke Kendaraan
CREATE INDEX idx_kontrak_status
    ON Kontrak_Sewa(status_sewa, id_kendaraan);

-- [INDEX] Ambil log terbaru per Kendaraan secara efisien
CREATE INDEX idx_lokasi_kendaraan_waktu
    ON Pelacakan_Lokasi(id_kendaraan, waktu_log DESC);

-- [INDEX] Filter baris dengan sinyal hilang
CREATE INDEX idx_lokasi_sinyal
    ON Pelacakan_Lokasi(status_sinyal);

-- CTE menggantikan nested subquery agar lebih efisien
WITH log_terbaru AS (
    -- Pelacakan_Lokasi: ambil 1 log GPS terbaru per Kendaraan
    SELECT id_kendaraan, waktu_log, status_sinyal,
           ROW_NUMBER() OVER (PARTITION BY id_kendaraan ORDER BY waktu_log DESC) AS rn
    FROM Pelacakan_Lokasi
),
sewa_aktif AS (
    -- Kontrak_Sewa + Pelanggan: hanya sewa yang masih berjalan
    SELECT ks.id_sewa, ks.id_kendaraan, ks.status_sewa,
           CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
           p.no_telp
    FROM Kontrak_Sewa ks
    JOIN Pelanggan p ON ks.id_pelanggan = p.id_pelanggan
    WHERE ks.status_sewa IN ('aktif', 'terlambat')
)
SELECT
    k.plat_nomor,
    k.merk,
    sa.status_sewa,
    sa.nama_pelanggan,
    sa.no_telp,
    lt.waktu_log  AS terakhir_kirim_sinyal,
    lt.status_sinyal,
    TIMESTAMPDIFF(HOUR, lt.waktu_log, NOW()) AS jam_tidak_terdeteksi
-- Kendaraan: identitas unit fisik Kendaraan
FROM Kendaraan k
JOIN sewa_aktif sa   ON k.id_kendaraan = sa.id_kendaraan
LEFT JOIN log_terbaru lt ON k.id_kendaraan = lt.id_kendaraan AND lt.rn = 1
WHERE lt.status_sinyal = 'hilang'
   OR lt.waktu_log IS NULL
   OR TIMESTAMPDIFF(HOUR, lt.waktu_log, NOW()) > 24
ORDER BY jam_tidak_terdeteksi DESC
LIMIT 20;


-- ============================================================
--  TRIGGER & EVENT PENDUKUNG QUERY 1
-- ============================================================

-- [TRIGGER] Otomatis catat ke log_anomali saat sinyal
-- masuk dengan status 'hilang'
DROP TRIGGER IF EXISTS trg_after_lokasi_insert;
DELIMITER //
CREATE TRIGGER trg_after_lokasi_insert
AFTER INSERT ON Pelacakan_Lokasi
FOR EACH ROW
BEGIN
    IF NEW.status_sinyal = 'hilang' THEN
        -- log_anomali: catat kejadian GPS hilang untuk kontrak aktif
        -- kolom waktu_log sesuai PDM (bukan waktu_kejadian)
        INSERT INTO log_anomali
            (id_sewa, jenis_anomali, waktu_log, deskripsi, skor_risiko, status_tindak_lanjut)
        SELECT
            ks.id_sewa,
            'GPS Hilang',
            NOW(),
            CONCAT('Sinyal GPS Kendaraan ', k.plat_nomor, ' hilang pada ', NEW.waktu_log),
            70,
            'Perlu Ditinjau'
        FROM Kontrak_Sewa ks
        JOIN Kendaraan k ON ks.id_kendaraan = k.id_kendaraan
        WHERE ks.id_kendaraan = NEW.id_kendaraan
          AND ks.status_sewa IN ('aktif', 'terlambat')
        LIMIT 1;
    END IF;
END //
DELIMITER ;

-- [EVENT] Aktifkan scheduler (jalankan sekali di server)
SET GLOBAL event_scheduler = ON;

-- [EVENT] Tiap 5 menit: tandai sinyal 'hilang' jika tidak ada
-- kiriman log baru dari Kendaraan aktif selama > 5 menit
DROP EVENT IF EXISTS evt_ping_lokasi;
DELIMITER //
CREATE EVENT evt_ping_lokasi
ON SCHEDULE EVERY 5 MINUTE
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE Pelacakan_Lokasi pl
    JOIN (
        SELECT id_kendaraan, MAX(waktu_log) AS last_log
        FROM Pelacakan_Lokasi
        GROUP BY id_kendaraan
    ) latest ON pl.id_kendaraan = latest.id_kendaraan
             AND pl.waktu_log   = latest.last_log
    SET pl.status_sinyal = 'hilang'
    WHERE TIMESTAMPDIFF(MINUTE, latest.last_log, NOW()) > 5
      AND pl.status_sinyal != 'hilang'
      AND pl.id_kendaraan IN (
          SELECT id_kendaraan FROM Kontrak_Sewa
          WHERE status_sewa IN ('aktif', 'terlambat')
      );
END //
DELIMITER ;

-- [EVENT] Tiap 1 hari: hapus data lokasi yang sudah > 7 hari
-- agar tabel Pelacakan_Lokasi tidak membengkak
DROP EVENT IF EXISTS evt_hapus_lokasi_lama;
DELIMITER //
CREATE EVENT evt_hapus_lokasi_lama
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM Pelacakan_Lokasi
    WHERE waktu_log < DATE_SUB(NOW(), INTERVAL 7 DAY);
END //
DELIMITER ;


-- ============================================================
--  QUERY 2: LAPORAN PELANGGARAN GEOFENCE
--  Rekap Pelanggan dengan >= 2 pelanggaran batas wilayah
--  pada sewa yang masih aktif atau bermasalah.
-- ============================================================

-- ---- SEBELUM OPTIMASI ----
-- GROUP BY langsung di atas tabel besar, tanpa pre-agregasi
SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.no_telp,
    k.plat_nomor,
    ks.id_sewa,
    ks.status_sewa,
    -- Konfigurasi_Geofence: radius batas wilayah yang disepakati
    kg.radius_km AS batas_geofence_km,
    COUNT(pg.id_pelanggaran)     AS total_pelanggaran,
    MAX(pg.jarak_pelanggaran_km) AS jarak_terjauh_km,
    GROUP_CONCAT(DISTINCT pg.status_penanganan ORDER BY pg.status_penanganan) AS status_penanganan_list
-- Pelanggaran_Geofence: data log setiap pelanggaran batas wilayah
FROM Pelanggaran_Geofence pg
-- Kontrak_Sewa: filter sewa yang masih aktif/bermasalah
JOIN Kontrak_Sewa ks ON pg.id_sewa = ks.id_sewa
-- Pelanggan: identitas Pelanggan pelanggar
JOIN Pelanggan p     ON ks.id_pelanggan = p.id_pelanggan
-- Kendaraan: Kendaraan yang dipakai
JOIN Kendaraan k     ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN Konfigurasi_Geofence kg ON ks.id_sewa = kg.id_sewa
WHERE ks.status_sewa IN ('aktif', 'terlambat', 'proses hukum')
GROUP BY p.nik, nama_pelanggan, p.no_telp, k.plat_nomor,
         ks.id_sewa, ks.status_sewa, kg.radius_km
HAVING COUNT(pg.id_pelanggaran) >= 2
ORDER BY total_pelanggaran DESC
LIMIT 20;


-- ---- SESUDAH OPTIMASI ----

-- [INDEX] JOIN utama pelanggaran -> kontrak sewa
CREATE INDEX idx_pelanggaran_sewa
    ON Pelanggaran_Geofence(id_sewa);

-- [INDEX] Filter status sewa
CREATE INDEX idx_kontrak_status_q2
    ON Kontrak_Sewa(status_sewa);

-- [INDEX] Sorting & agregasi jarak
CREATE INDEX idx_pelanggaran_jarak
    ON Pelanggaran_Geofence(jarak_pelanggaran_km);

-- Tabel ringkasan pre-agregasi (materialized view manual)
-- Pelanggaran_Geofence diringkas per id_sewa agar query utama
-- tidak GROUP BY di atas tabel besar setiap kali dijalankan
CREATE TABLE IF NOT EXISTS ringkasan_pelanggaran (
    id_sewa                INT PRIMARY KEY,
    total_pelanggaran      INT DEFAULT 0,
    jarak_terjauh_km       DECIMAL(10,2),
    pelanggaran_terakhir   DATETIME,
    status_penanganan_list TEXT,
    INDEX idx_total (total_pelanggaran DESC)
);

-- Isi ringkasan: jalankan sekali untuk inisialisasi,
-- selanjutnya diperbarui otomatis via trigger insert pelanggaran
REPLACE INTO ringkasan_pelanggaran
SELECT
    id_sewa,
    COUNT(id_pelanggaran),
    MAX(jarak_pelanggaran_km),
    MAX(waktu_pelanggaran),
    GROUP_CONCAT(DISTINCT status_penanganan ORDER BY status_penanganan)
FROM Pelanggaran_Geofence
GROUP BY id_sewa
HAVING COUNT(id_pelanggaran) >= 2;

-- Query utama: JOIN ke ringkasan, bukan scan tabel besar
SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    k.plat_nomor,
    ks.status_sewa,
    -- Konfigurasi_Geofence: radius batas wilayah yang disepakati
    kg.radius_km AS batas_km,
    rp.total_pelanggaran,
    rp.jarak_terjauh_km,
    rp.status_penanganan_list,
    CASE
        WHEN rp.total_pelanggaran >= 5 THEN 'KRITIS'
        WHEN rp.total_pelanggaran >= 3 THEN 'TINGGI'
        ELSE 'SEDANG'
    END AS tingkat_risiko
-- ringkasan_pelanggaran: sumber data pra-agregasi
FROM ringkasan_pelanggaran rp
-- Kontrak_Sewa: filter sewa yang masih aktif/bermasalah
JOIN Kontrak_Sewa ks ON rp.id_sewa = ks.id_sewa
-- Pelanggan: identitas penyewa
JOIN Pelanggan p     ON ks.id_pelanggan = p.id_pelanggan
-- Kendaraan: unit Kendaraan yang dipakai
JOIN Kendaraan k     ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN Konfigurasi_Geofence kg ON ks.id_sewa = kg.id_sewa
WHERE ks.status_sewa IN ('aktif', 'terlambat', 'proses hukum')
ORDER BY rp.total_pelanggaran DESC
LIMIT 20;


-- ============================================================
--  QUERY 3: CROSS-CHECK NIK DENGAN BLACKLIST KOMUNITAS
--  Mendeteksi Pelanggan aktif yang NIK-nya cocok dengan
--  daftar hitam terverifikasi dari komunitas rental.
-- ============================================================

-- ---- SEBELUM OPTIMASI ----
-- JOIN langsung ke Daftar_Hitam tanpa filter awal,
-- memproses seluruh 10.000 baris blacklist
SELECT
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    p.status_akun,
    ks.id_sewa,
    ks.status_sewa,
    k.plat_nomor,
    k.status_kendaraan,
    -- Daftar_Hitam: detail pelanggaran yang dilaporkan
    dh.nama_lengkap      AS nama_di_blacklist,
    dh.jenis_pelanggaran,
    dh.tanggal_kejadian,
    dh.status_verifikasi,
    -- Komunitas_Rental: rental mana yang melaporkan NIK ini
    kr.nama_rental       AS rental_pelapor,
    kr.kota              AS kota_rental_pelapor
-- Pelanggan: sumber NIK penyewa yang sedang aktif
FROM Pelanggan p
-- Kontrak_Sewa: filter sewa yang masih berjalan
JOIN Kontrak_Sewa ks  ON p.id_pelanggan = ks.id_pelanggan
-- Kendaraan: Kendaraan yang sedang dipakai
JOIN Kendaraan k      ON ks.id_kendaraan = k.id_kendaraan
JOIN Daftar_Hitam dh  ON p.nik = dh.nik
JOIN Komunitas_Rental kr ON dh.id_rental_pelapor = kr.id_rental
WHERE ks.status_sewa IN ('aktif', 'terlambat', 'dipesan')
  AND dh.status_verifikasi = 'terverifikasi'
ORDER BY dh.tanggal_kejadian DESC
LIMIT 20;


-- ---- SESUDAH OPTIMASI ----

-- [INDEX] JOIN VARCHAR NIK: Pelanggan <-> Daftar_Hitam
CREATE INDEX idx_pelanggan_nik
    ON Pelanggan(nik);

-- [INDEX] Filter + JOIN pada tabel blacklist
CREATE INDEX idx_blacklist_nik
    ON Daftar_Hitam(nik, status_verifikasi);

-- [INDEX] Sorting berdasarkan tanggal kejadian
CREATE INDEX idx_blacklist_tgl
    ON Daftar_Hitam(tanggal_kejadian DESC);

-- [INDEX] Filter status sewa + join ke Pelanggan
CREATE INDEX idx_kontrak_status_p
    ON Kontrak_Sewa(status_sewa, id_pelanggan);

-- CTE: filter blacklist terverifikasi lebih awal
-- agar JOIN tidak memproses seluruh 10.000 baris Daftar_Hitam

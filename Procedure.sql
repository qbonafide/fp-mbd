USE fp_rental_kendaraan;

DROP PROCEDURE IF EXISTS proc_proses_kendaraan_hilang;

DELIMITER $$

CREATE PROCEDURE proc_proses_kendaraan_hilang(
    IN p_id_kendaraan INT,
    IN p_deskripsi TEXT)

BEGIN
DECLARE v_id_sewa INT;
DECLARE v_id_pelanggan INT;
DECLARE v_skor INT;
START TRANSACTION;

SELECT
ks.id_sewa,
ks.id_pelanggan
INTO
v_id_sewa,
v_id_pelanggan
FROM kontrak_sewa ks
WHERE ks.id_kendaraan=p_id_kendaraan
AND ks.status_sewa IN ('Aktif','Terlambat')
LIMIT 1;

UPDATE kendaraan
SET status_kendaraan='Hilang'
WHERE id_kendaraan=p_id_kendaraan;

UPDATE kontrak_sewa
SET status_sewa='Macet-Hukum'
WHERE id_sewa=v_id_sewa;

INSERT INTO log_anomali
(id_sewa,jenis_anomali,waktu_log,deskripsi,skor_risiko,status_tindak_lanjut)
VALUES
(v_id_sewa,'KENDARAAN_HILANG',NOW(),p_deskripsi,50,'Prioritas Tinggi');

SET v_skor = fn_hitung_skor_risiko_pelanggan(v_id_pelanggan);

IF v_skor >= 90 THEN
UPDATE pelanggan
SET status_akun='Diblokir'
WHERE id_pelanggan=v_id_pelanggan;

ELSEIF v_skor >=70 THEN
UPDATE pelanggan
SET status_akun='Ditangguhkan'
WHERE id_pelanggan=v_id_pelanggan;

END IF;

COMMIT;
END$$

DELIMITER ;

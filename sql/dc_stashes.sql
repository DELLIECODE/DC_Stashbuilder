CREATE TABLE IF NOT EXISTS `dc_stashes` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `stash_name` VARCHAR(64) NOT NULL,
  `label` VARCHAR(64) NOT NULL,
  `slots` INT NOT NULL DEFAULT 50,
  `weight` INT NOT NULL DEFAULT 100000,
  `coords` LONGTEXT NOT NULL,
  `distance` FLOAT NOT NULL DEFAULT 2.0,
  `access_type` ENUM('public','job','personal') NOT NULL DEFAULT 'public',
  `job` TEXT DEFAULT NULL,
  `min_grade` INT NOT NULL DEFAULT 0,
  `created_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_stash_name` (`stash_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Run these two lines once on an existing database.
ALTER TABLE `dc_stashes` MODIFY `access_type` ENUM('public','job','personal') NOT NULL DEFAULT 'public';
ALTER TABLE `dc_stashes` MODIFY `job` TEXT DEFAULT NULL;

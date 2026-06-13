-- ============================================================================
-- Wasteland Survivors — Seed Data v2.0
-- Populates the v2 schema with demo/test data.
-- Run AFTER wasteland_survivors_schema_v2.sql
-- ============================================================================

USE `wasteland_survivors`;

-- ============================================================================
-- PLAYERS (demo accounts)
-- Password for both: "password123" (BCrypt hashed)
-- In production, passwords are hashed by AuthServiceImpl, not inserted manually.
--
-- TIP: Instead of logging in with seed accounts, just REGISTER a new account
--      via the Unity login screen — registration always works and logs you in.
--      Seed accounts exist for quick demo/testing convenience only.
--
-- NOTE: Health values are stored in player_world_state (3NF), NOT in players.
--       Default HP (20) is set when the player first enters a world.
-- ============================================================================
INSERT INTO `players` (`username`, `password_hash`, `has_played_intro`) VALUES
('demo_owner', '$2a$10$imOgdg0fcNfsgp4yXP68iOd5wMPwgCkmvJDK00qZ12eLesmcDQvM6', FALSE),
('demo_guest', '$2a$10$FjhddihIGOjJjk0UxQr.q.90unMboATI1AKyjW878LSWLgqIBqBoi', FALSE);


-- ============================================================================
-- WORLDS
-- ============================================================================
INSERT INTO `worlds` (`id`, `owner_id`, `world_name`) VALUES
('WORLD_001', 1, 'Demo World');


-- ============================================================================
-- PLAYER WORLD STATE (initial spawn positions and stats)
-- ============================================================================
INSERT INTO `player_world_state` (`player_id`, `world_id`, `current_health`, `max_health`, `damage`, `weapon_range`, `speed`, `position_x`, `position_y`, `facing_direction`, `current_scene`) VALUES
(1, 'WORLD_001', 20, 20, 1.0, 3.5, 5.0, 0.0, 0.0, 1, 'Interior_02'),
(2, 'WORLD_001', 20, 20, 1.0, 3.5, 5.0, 2.5, 0.0, -1, 'Interior_02');


-- ============================================================================
-- PLAYER PROGRESSION
-- ============================================================================
INSERT INTO `player_progression` (`player_id`, `world_id`, `experience`, `level`, `exp_to_level`, `exp_growth_multiplier`) VALUES
(1, 'WORLD_001', 0, 1, 10, 1.2),
(2, 'WORLD_001', 0, 1, 10, 1.2);


-- ============================================================================
-- ITEM DEFINITIONS (master catalog)
-- ============================================================================
INSERT INTO `item_definitions` (`item_id`, `item_name`, `item_type`, `rarity`, `stat_to_change`, `amount_to_change_stat`, `max_stack`, `sprite_name`, `item_description`) VALUES
('HEALTHPACK',  'Health Pack',  'consumable', 'common',   'health', 10, 9,  'healthpack_sprite',  'A basic med kit. Restores 10 HP. Cannot be used at full health.'),
('GOLD_BAR',    'Gold Bar',     'valuable',   'uncommon', 'none',    0, 99, 'goldbar_sprite',     'A shiny gold bar. Valuable, but has no direct use effect.'),
('AMMO_PISTOL', 'Pistol Ammo',  'ammo',       'common',   'none',    0, 99, 'ammo_pistol_sprite', 'Standard pistol ammunition.');


-- ============================================================================
-- INVENTORIES (header rows — one per player per world)
-- The JPA entity InventoryEntity maps to this table. Items are in inventory_items.
-- ============================================================================
INSERT INTO `inventories` (`player_id`, `world_id`) VALUES
(1, 'WORLD_001'),
(2, 'WORLD_001');

-- ============================================================================
-- INVENTORY ITEMS (demo items for demo_owner in WORLD_001)
-- inventory_id=1 is demo_owner's inventory; items link via inventory_id FK.
-- ============================================================================
INSERT INTO `inventory_items` (`inventory_id`, `item_id`, `item_name`, `quantity`, `item_description`, `sprite_name`) VALUES
(1, 'HEALTHPACK',  'Health Pack',  2,  'A basic med kit. Restores 10 HP.', 'healthpack_sprite'),
(1, 'AMMO_PISTOL', 'Pistol Ammo',  30, 'Standard pistol ammunition.',       'ammo_pistol_sprite');


-- ============================================================================
-- ENEMY TYPES (catalog matching Unity prefabs)
-- ============================================================================
INSERT INTO `enemy_types` (`type_id`, `display_name`, `base_health`, `base_damage`, `base_speed`, `base_attack_range`, `base_detect_range`, `base_attack_cooldown`, `exp_reward`, `is_boss`, `native_sprite_facing_sign`, `prefab_name`, `spawn_weight`) VALUES
('ZOMBIE_VARIANT_01',        'Zombie',           5,  1, 2.0, 1.2, 5.0, 2.0, 3,  FALSE, 1,  'Zombie_variant_01',          10),
('ZOMBIE_VARIANT_01_TYPE02', 'Zombie (Type 02)', 7,  2, 2.2, 1.3, 5.5, 1.8, 5,  FALSE, 1,  'Zombie_variant_01_Type_02', 6),
('ZOMBIE_TYPE03',            'Zombie (Type 03)', 10, 3, 1.8, 1.5, 6.0, 2.5, 8,  FALSE, 1,  'ZombieType03',              4),
('WALK1',                    'Walker',           3,  1, 1.5, 0.8, 4.0, 1.5, 2,  FALSE, 1,  'Walk1',                     8),
('BOSS_MUTATED',             'Mutated Boss',     30, 4, 2.5, 2.0, 8.0, 3.0, 50, TRUE, -1, 'Zombie_variant_01',         1);


-- ============================================================================
-- ENEMY INSTANCES (runtime enemies in WORLD_001)
-- ============================================================================
INSERT INTO `enemy_instances` (`world_id`, `type_id`, `current_health`, `position_x`, `position_y`, `facing_direction`, `enemy_state`) VALUES
('WORLD_001', 'ZOMBIE_VARIANT_01', 5,  5.0,  0.0,  -1, 'IDLE'),
('WORLD_001', 'ZOMBIE_VARIANT_01', 5,  8.0,  1.5,  -1, 'IDLE'),
('WORLD_001', 'ZOMBIE_VARIANT_01', 5,  12.0, -2.0, -1, 'IDLE'),
('WORLD_001', 'ZOMBIE_TYPE03',     10, 15.0, 3.0,  -1, 'IDLE'),
('WORLD_001', 'BOSS_MUTATED',      30, 20.0, 0.0,   1, 'IDLE');


-- ============================================================================
-- BOSS ENCOUNTERS (one per world) — two-phase boss fight
-- Phase 1: normal → Phase 2: (triggered at 0 HP) → scream + restore to phase2_health + stat buffs
-- ============================================================================
INSERT INTO `boss_encounters` (`world_id`, `boss_enemy_id`, `fight_started`, `current_phase`, `phase2_activated`, `phase2_health`, `phase2_speed_multiplier`, `is_defeated`) VALUES
('WORLD_001', 5, FALSE, 1, FALSE, 100, 1.5, FALSE);  -- enemy_id 5 is the BOSS_MUTATED instance above


-- ============================================================================
-- QUESTS (Sara quest + Quest2 per world)
-- ============================================================================
INSERT INTO `quests` (`world_id`, `quest_id`, `quest_state`, `zombies_remaining`, `is_boss_alive`) VALUES
('WORLD_001', 'sara_village', 0, 12, TRUE),
('WORLD_001', 'quest2',       0, 0,  FALSE);


-- ============================================================================
-- NPC ACTORS
-- ============================================================================
INSERT INTO `npc_actors` (`actor_id`, `actor_name`, `portrait_sprite_name`) VALUES
('SARA',    'Sara',     'sara_portrait'),
('JOEL',    'Joel',     'joel_portrait'),
('NARRATOR','Narrator', NULL);


-- ============================================================================
-- DIALOGUE TREES (Sara quest dialogues)
-- ============================================================================
INSERT INTO `dialogue_trees` (`dialogue_id`, `npc_actor_id`, `quest_state_filter`, `description`) VALUES
('SARA_INTRO',    'SARA', 0, 'Sara greets the player and offers the quest'),
('SARA_WAITING',  'SARA', 1, 'Sara reminds the player to clear the village'),
('SARA_COMPLETE', 'SARA', 2, 'Sara congratulates the player and gives reward');


-- ============================================================================
-- DIALOGUE LINES (ordered by line_index within each dialogue)
-- ============================================================================
-- SARA_INTRO: Quest offer
INSERT INTO `dialogue_lines` (`dialogue_id`, `line_index`, `actor_id`, `line_text`) VALUES
('SARA_INTRO', 0, 'SARA', 'Oh, thank goodness you are here!'),
('SARA_INTRO', 1, 'SARA', 'The village has been overrun by the undead. We need your help.'),
('SARA_INTRO', 2, 'SARA', 'There are about a dozen zombies out there... and something much worse.'),
('SARA_INTRO', 3, 'SARA', 'A mutated boss creature. Take them all down and I will make it worth your while.');

-- SARA_WAITING: Reminder while quest is active
INSERT INTO `dialogue_lines` (`dialogue_id`, `line_index`, `actor_id`, `line_text`) VALUES
('SARA_WAITING', 0, 'SARA', 'The village is still dangerous. Please, clear out those zombies!'),
('SARA_WAITING', 1, 'SARA', 'I will be here when the job is done.');

-- SARA_COMPLETE: Quest hand-in
INSERT INTO `dialogue_lines` (`dialogue_id`, `line_index`, `actor_id`, `line_text`) VALUES
('SARA_COMPLETE', 0, 'SARA', 'You did it! The village is safe thanks to you.'),
('SARA_COMPLETE', 1, 'SARA', 'As promised, here is your reward. You have earned it.');


-- ============================================================================
-- DIALOGUE OPTIONS (branching choices at end of dialogues)
-- ============================================================================
-- SARA_INTRO: Accept or decline
INSERT INTO `dialogue_options` (`dialogue_id`, `option_index`, `option_text`, `next_dialogue_id`) VALUES
('SARA_INTRO',    0, 'I will help. Count on me.', NULL),  -- NULL = end dialogue (accepts quest via FinishSaraQuest)
('SARA_INTRO',    1, 'Not right now.',            NULL);  -- NULL = end dialogue (declines for now)

-- SARA_WAITING: Only option is to end
INSERT INTO `dialogue_options` (`dialogue_id`, `option_index`, `option_text`, `next_dialogue_id`) VALUES
('SARA_WAITING',  0, 'I am working on it.', NULL);

-- SARA_COMPLETE: Take reward
INSERT INTO `dialogue_options` (`dialogue_id`, `option_index`, `option_text`, `next_dialogue_id`) VALUES
('SARA_COMPLETE', 0, 'Thank you, Sara!', NULL);  -- hands in quest, spawns reward item


-- ============================================================================
-- MULTIPLAYER SESSIONS (one demo session)
-- ============================================================================
INSERT INTO `sessions` (`session_id`, `join_key`, `status`, `owner_id`, `guest_id`, `world_id`) VALUES
('SESSION_DEMO_001', 'ABC123', 'WAITING', 1, NULL, 'WORLD_001');


-- ============================================================================
-- PLAYER AMMO (per-world ammo state for demo players)
-- 3NF: separated from player_world_state — ammo changes independently of position/health
-- Unity source: Player_Combat.cs (currentClip, maxClipSize, totalAmmoReserve)
-- ============================================================================
INSERT INTO `player_ammo` (`player_id`, `world_id`, `current_clip`, `max_clip_size`, `total_ammo_reserve`, `updated_at`) VALUES
(1, 'WORLD_001', 30, 30, 60, CURRENT_TIMESTAMP),
(2, 'WORLD_001', 30, 30, 60, CURRENT_TIMESTAMP);


-- ============================================================================
-- ITEM DEFINITIONS — Ammo & Melee (added for melee/ammo update)
-- ============================================================================
INSERT INTO `item_definitions` (`item_id`, `item_name`, `item_type`, `rarity`, `stat_to_change`, `amount_to_change_stat`, `max_stack`, `sprite_name`, `item_description`) VALUES
('AMMO_SHOTGUN',  'Shotgun Shells',  'ammo',  'uncommon', 'none', 0, 20, 'ammo_shotgun_sprite',  'Shotgun ammunition. High damage, low capacity.'),
('AMMO_RIFLE',    'Rifle Rounds',    'ammo',  'common',   'none', 0, 60, 'ammo_rifle_sprite',    'Standard rifle ammunition. Balanced capacity and damage.'),
('MELEE_BAT',     'Baseball Bat',    'weapon', 'common',  'none', 0, 1,  'bat_sprite',           'A sturdy baseball bat. Deals 2 melee damage and knocks enemies back.');


-- ============================================================================
-- END OF SEED DATA
-- ============================================================================
-- Verify with:
--   SELECT COUNT(*) FROM players;          -- should be 2
--   SELECT COUNT(*) FROM enemy_types;      -- should be 5
--   SELECT COUNT(*) FROM enemy_instances;  -- should be 5
--   SELECT COUNT(*) FROM dialogue_trees;   -- should be 3
--   SELECT COUNT(*) FROM dialogue_lines;   -- should be 8
--   SELECT COUNT(*) FROM player_ammo;      -- should be 2
--   SELECT COUNT(*) FROM item_definitions; -- should be 6
--   SELECT COUNT(*) FROM inventories;      -- should be 2
--   SELECT COUNT(*) FROM inventory_items;  -- should be 2
--   SELECT COUNT(*) FROM quests;           -- should be 2 (sara_village + quest2)
--   SELECT * FROM boss_encounters;         -- current_phase=1, phase2_activated=0
-- ============================================================================
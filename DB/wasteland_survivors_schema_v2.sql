-- ============================================================================
-- Wasteland Survivors — Database Schema v2.0
-- MySQL 8.0+ | 3NF Normalised | Professionally Commented
-- ============================================================================
--
-- DESIGN PRINCIPLES:
--  1. Third Normal Form (3NF): Every non-key column depends on the key,
--     the whole key, and nothing but the key. No transitive dependencies.
--  2. No duplicated data: Item names, enemy stats, NPC identities live
--     in their definition tables exactly once. Runtime state references
--     definitions via foreign keys.
--  3. Per-world scoping: Player stats, inventory, quest progress, and
--     enemy instances are all scoped to a specific world. A player can
--     have different stats in different worlds.
--  4. Naming convention: snake_case for all columns and tables.
--     Primary keys are `id` (surrogate) or natural keys where appropriate.
--     Foreign keys follow the pattern `referenced_table_name_id`.
--  5. Every table and column has a comment explaining what it stores
--     and which Unity script/variable it maps to.
--
-- HOW TO READ THIS FILE (for beginners):
--  - PK = Primary Key (uniquely identifies each row)
--  - FK = Foreign Key (references a PK in another table)
--  - UNIQUE = No two rows can have the same value in this column
--  - NOT NULL = This column must always have a value
--  - DEFAULT = If no value is provided, this default is used
--  - Look for the --> arrows: they show which Unity variable maps here
--
-- ============================================================================

-- Create the database if it doesn't already exist.
-- Character set utf8mb4 supports emoji and special characters in text.
CREATE DATABASE IF NOT EXISTS `wasteland_survivors`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `wasteland_survivors`;

-- ============================================================================
-- IDEMPOTENCY: Drop existing tables in reverse-dependency order.
-- This ensures the script can be run repeatedly without errors.
-- Tables are dropped child-first so FK constraints don't block the DROP.
-- WARNING: This destroys all existing data. For production, use migration tools
-- (Flyway/Liquibase) instead of DROP-and-recreate.
-- ============================================================================
DROP TABLE IF EXISTS `dialogue_options`;
DROP TABLE IF EXISTS `dialogue_lines`;
DROP TABLE IF EXISTS `dialogue_trees`;
DROP TABLE IF EXISTS `sessions`;
DROP TABLE IF EXISTS `persistent_objects`;
DROP TABLE IF EXISTS `quests`;
DROP TABLE IF EXISTS `boss_encounters`;
DROP TABLE IF EXISTS `enemy_instances`;
DROP TABLE IF EXISTS `enemy_types`;
DROP TABLE IF EXISTS `inventory_items`;
DROP TABLE IF EXISTS `inventories`;
DROP TABLE IF EXISTS `item_definitions`;
DROP TABLE IF EXISTS `player_progression`;
DROP TABLE IF EXISTS `player_ammo`;
DROP TABLE IF EXISTS `player_world_state`;
DROP TABLE IF EXISTS `worlds`;
DROP TABLE IF EXISTS `npc_actors`;
DROP TABLE IF EXISTS `players`;

-- ============================================================================
-- SECTION 1: PLAYER IDENTITY & AUTHENTICATION
-- ============================================================================

-- Stores player account credentials and profile-level settings.
-- This is the "who you are" table — one row per registered player.
-- Unity source: MockLoginManager.cs, GameAPI.cs (LocalPlayerId)
CREATE TABLE IF NOT EXISTS `players` (
    `id`                BIGINT          NOT NULL AUTO_INCREMENT  COMMENT 'Unique player identifier. --> GameAPI.LocalPlayerId, AuthResponse.playerId',
    `username`          VARCHAR(50)     NOT NULL                 COMMENT 'Login name chosen by the player. Must be unique. --> LoginRequest.username',
    `password_hash`     VARCHAR(255)    NOT NULL                 COMMENT 'BCrypt-hashed password. NEVER stores plain text. Verified by AuthServiceImpl on login.',
    `has_played_intro`  BOOLEAN         NOT NULL DEFAULT FALSE  COMMENT 'Whether this player has seen the opening cutscene. --> IntroDialogueTrigger.hasPlayedIntro (static)',
    `created_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the account was created via /auth/register',
    `last_login_at`     TIMESTAMP       NULL                     COMMENT 'When the player last logged in. Updated on every successful /auth/login',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_players_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Player accounts — authentication and profile-level settings.';


-- ============================================================================
-- SECTION 2: WORLD MANAGEMENT
-- ============================================================================

-- Stores world metadata. A world is a game instance owned by one player.
-- Multiplayer sessions happen within a world.
-- Unity source: WorldService, GameManager.cs
CREATE TABLE IF NOT EXISTS `worlds` (
    `id`                VARCHAR(64)     NOT NULL                 COMMENT 'Unique world identifier. Format: WORLD_ plus digits, e.g. WORLD_001. --> worldId in all DTOs',
    `owner_id`          BIGINT          NOT NULL                 COMMENT 'The player who created and owns this world. FK: players.id',
    `world_name`        VARCHAR(100)    NOT NULL                 COMMENT 'Display name chosen by the owner, e.g. "Demo World"',
    `created_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the world was created via /worlds/create',
    `updated_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last time any data in this world changed (auto-updated)',

    PRIMARY KEY (`id`),
    CONSTRAINT `fk_worlds_owner` FOREIGN KEY (`owner_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='World metadata — one row per game world instance.';


-- ============================================================================
-- SECTION 3: PLAYER STATE PER WORLD
-- ============================================================================

-- Stores the runtime state of a player within a specific world.
-- This is separate from `players` because a player can be in multiple worlds
-- with different stats, positions, and scenes.
-- Unity source: StatsManager.cs, Player_Health.cs, player_movement.cs, SceneChanger.cs
CREATE TABLE IF NOT EXISTS `player_world_state` (
    `id`                BIGINT          NOT NULL AUTO_INCREMENT  COMMENT 'Surrogate PK for this state record',
    `player_id`         BIGINT          NOT NULL                 COMMENT 'Which player this state belongs to. FK: players.id',
    `world_id`          VARCHAR(64)     NOT NULL                 COMMENT 'Which world this state is for. FK: worlds.id',

    -- Health --> StatsManager.currentHealth / maxHealth, Player_Health.cs
    `current_health`    INT             NOT NULL DEFAULT 20      COMMENT 'Current HP. --> StatsManager.currentHealth',
    `max_health`        INT             NOT NULL DEFAULT 20      COMMENT 'Maximum HP. --> StatsManager.maxHealth',

    -- Combat stats --> StatsManager.damage / weaponRange
    `damage`            FLOAT           NOT NULL DEFAULT 1.0     COMMENT 'Attack damage per hit before frenzy scaling. --> StatsManager.damage, Player_Combat.damage',
    `weapon_range`      FLOAT           NOT NULL DEFAULT 3.5     COMMENT 'Weapon attack radius in Unity units. --> StatsManager.weaponRange, Player_Combat.weaponRange',

    -- Movement --> StatsManager.speed, player_movement.speed
    `speed`             FLOAT           NOT NULL DEFAULT 5.0     COMMENT 'Movement speed. --> StatsManager.speed, player_movement.speed',

    -- Position --> player_movement.transform.position + facingDirection
    `position_x`        FLOAT           NOT NULL DEFAULT 0.0     COMMENT 'X coordinate in the current scene. --> PositionDTO.x',
    `position_y`        FLOAT           NOT NULL DEFAULT 0.0     COMMENT 'Y coordinate in the current scene. --> PositionDTO.y',
    `facing_direction`  INT             NOT NULL DEFAULT 1       COMMENT '1 = facing right, -1 = facing left. --> player_movement.facingDirection',

    -- Scene tracking --> SceneChanger.sceneToLoad
    `current_scene`     VARCHAR(100)    NULL                     COMMENT 'The Unity scene the player is currently in, e.g. "Interior_02". --> SceneChanger.sceneToLoad',

    `updated_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last time this state was saved',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_player_world` (`player_id`, `world_id`),
    CONSTRAINT `fk_pws_player` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_pws_world`  FOREIGN KEY (`world_id`)  REFERENCES `worlds`  (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Player runtime state per world — health, stats, position, scene.';


-- ============================================================================
-- SECTION 3A: PLAYER AMMUNITION (PER WORLD)
-- ============================================================================

-- Stores ammunition state per player per world.
-- 3NF: separated from player_world_state because ammo changes at different
-- frequency than position/health and to avoid lock contention during combat.
-- Unity source: Player_Combat.cs (currentClip, maxClipSize, totalAmmoReserve)
CREATE TABLE IF NOT EXISTS `player_ammo` (
    `id`                    BIGINT      NOT NULL AUTO_INCREMENT  COMMENT 'Surrogate PK',
    `player_id`             BIGINT      NOT NULL                 COMMENT 'FK: players.id',
    `world_id`              VARCHAR(64) NOT NULL                 COMMENT 'FK: worlds.id',

    -- --> Player_Combat.currentClip / maxClipSize / totalAmmoReserve
    `current_clip`          INT         NOT NULL DEFAULT 30      COMMENT 'Bullets currently in the magazine. --> Player_Combat.currentClip',
    `max_clip_size`         INT         NOT NULL DEFAULT 30      COMMENT 'Maximum magazine capacity. --> Player_Combat.maxClipSize',
    `total_ammo_reserve`    INT         NOT NULL DEFAULT 60      COMMENT 'Total spare bullets carried. --> Player_Combat.totalAmmoReserve',

    `updated_at`            TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_ammo_player_world` (`player_id`, `world_id`),
    CONSTRAINT `fk_ammo_player` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_ammo_world`  FOREIGN KEY (`world_id`)  REFERENCES `worlds`  (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Player ammunition per world — clip and reserve tracking.';


-- ============================================================================
-- SECTION 4: PLAYER PROGRESSION (EXP & LEVELING)
-- ============================================================================

-- Tracks experience points and level progression per player per world.
-- Separated from player_world_state because progression changes less frequently
-- than position/health, and keeping it separate avoids lock contention.
-- Unity source: ExpManager.cs
CREATE TABLE IF NOT EXISTS `player_progression` (
    `id`                    BIGINT      NOT NULL AUTO_INCREMENT  COMMENT 'Surrogate PK',
    `player_id`             BIGINT      NOT NULL                 COMMENT 'FK: players.id',
    `world_id`              VARCHAR(64) NOT NULL                 COMMENT 'FK: worlds.id',

    -- --> ExpManager.currentExp, ExpManager.level, ExpManager.expToLevel, ExpManager.expGrowthMultiplier
    `experience`            BIGINT      NOT NULL DEFAULT 0       COMMENT 'Total EXP earned so far. --> ExpManager.currentExp',
    `level`                 INT         NOT NULL DEFAULT 1       COMMENT 'Current player level. --> ExpManager.level',
    `exp_to_level`          BIGINT      NOT NULL DEFAULT 10      COMMENT 'EXP threshold needed for next level-up. --> ExpManager.expToLevel',
    `exp_growth_multiplier` FLOAT       NOT NULL DEFAULT 1.2     COMMENT 'Multiplier applied to expToLevel after each level-up. --> ExpManager.expGrowthMultiplier',

    `updated_at`            TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_prog_player_world` (`player_id`, `world_id`),
    CONSTRAINT `fk_prog_player` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_prog_world`  FOREIGN KEY (`world_id`)  REFERENCES `worlds`  (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Player EXP and level progression per world.';


-- ============================================================================
-- SECTION 5: ITEM CATALOG & INVENTORY
-- ============================================================================

-- Defines every item type that can exist in the game.
-- This is the "master catalog" — items in player inventories reference this.
-- Only the STATIC properties of an item belong here.
-- Unity source: ItemSO.cs, Item.cs, Item_healthPack.prefab, Item_Gold_valuable.prefab
CREATE TABLE IF NOT EXISTS `item_definitions` (
    `item_id`               VARCHAR(64)  NOT NULL                COMMENT 'Unique item identifier. e.g. "MEDKIT", "GOLD_BAR". --> ItemSO.itemName, InventoryItemDTO.itemId',
    `item_name`             VARCHAR(100) NOT NULL                COMMENT 'Human-readable display name. e.g. "Med Kit". --> ItemSO.itemName, Item.itemName',
    `item_type`             VARCHAR(32)  NOT NULL DEFAULT 'consumable' COMMENT 'Category: consumable, weapon, ammo, quest, valuable. --> Used for inventory filtering',
    `rarity`                VARCHAR(32)  NULL                    COMMENT 'Rarity tier: common, uncommon, rare, legendary. NULL for non-tiered items.',
    `stat_to_change`        VARCHAR(32)  NOT NULL DEFAULT 'none' COMMENT 'Which stat this item affects when used. Values: none, health, stamina. --> ItemSO.statToChange enum',
    `amount_to_change_stat` INT          NOT NULL DEFAULT 0      COMMENT 'Magnitude of stat change. e.g. 10 means +10 HP for a health item. --> ItemSO.amountToChangeStat',
    `max_stack`             INT          NOT NULL DEFAULT 1      COMMENT 'Maximum copies of this item per inventory slot. --> ItemSlot.maxNumberofItems (default 9)',
    `sprite_name`           VARCHAR(100) NULL                    COMMENT 'Identifier for the Unity sprite asset. --> Item.sprite, InventoryItemDTO.spriteName',
    `item_description`      TEXT         NULL                    COMMENT 'Flavour or instruction text shown in the inventory detail panel. --> Item.itemDescription',

    PRIMARY KEY (`item_id`),
    UNIQUE KEY `uk_itemdef_name` (`item_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Master catalog of all item types — static definition data.';


-- Inventory header — one row per player per world.
-- The JPA entity InventoryEntity maps to this table. Items are stored as child
-- rows in inventory_items, linked by inventory_id.
-- Unity source: InventoryManager.cs, InventoryDTO
CREATE TABLE IF NOT EXISTS `inventories` (
    `id`            BIGINT       NOT NULL AUTO_INCREMENT         COMMENT 'Surrogate PK',
    `player_id`     BIGINT       NOT NULL                        COMMENT 'FK: players.id — who owns this inventory',
    `world_id`      VARCHAR(64)  NOT NULL                        COMMENT 'FK: worlds.id — which world this inventory belongs to',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_inv_player_world` (`player_id`, `world_id`),
    CONSTRAINT `fk_inv_hdr_player` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_inv_hdr_world`  FOREIGN KEY (`world_id`)  REFERENCES `worlds`  (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Inventory header per player per world — items stored in inventory_items.';


-- Individual item stacks within a player's inventory.
-- Linked to inventories via inventory_id (FK).  Matches the JPA entity
-- InventoryItemEntity which maps to this table.
-- Unity source: InventoryManager.cs, ItemSlot.cs, InventoryItemDTO
CREATE TABLE IF NOT EXISTS `inventory_items` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Surrogate PK for this item stack',
    `inventory_id`      BIGINT       NOT NULL                    COMMENT 'FK: inventories.id — which inventory this stack belongs to',
    `item_id`           VARCHAR(64)  NOT NULL                    COMMENT 'Identifier for this item type (e.g. "HealthPack") --> InventoryItemDTO.itemId',
    `item_name`         VARCHAR(100) NOT NULL                    COMMENT 'Display name --> InventoryItemDTO.itemName',
    `quantity`          INT          NOT NULL DEFAULT 0          COMMENT 'Stack size --> InventoryItemDTO.quantity, ItemSlot.quantity',
    `item_description`  TEXT         NULL                        COMMENT 'Flavour text --> InventoryItemDTO.itemDescription',
    `sprite_name`       VARCHAR(100) NULL                        COMMENT 'Unity sprite asset identifier --> InventoryItemDTO.spriteName',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_invitem_inv_item` (`inventory_id`, `item_id`),
    CONSTRAINT `fk_invitem_inventory` FOREIGN KEY (`inventory_id`) REFERENCES `inventories` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_invitem_itemdef`   FOREIGN KEY (`item_id`)     REFERENCES `item_definitions` (`item_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Item stacks within a player inventory — linked to inventories header.';


-- ============================================================================
-- SECTION 6: ENEMY SYSTEM
-- ============================================================================

-- Catalog of enemy types with their base (template) stats.
-- When an enemy is spawned, enemy_instances copies/overrides values from here.
-- This is 3NF: the definition exists once, instances reference it.
-- Unity source: EnemyFollowPlayer.cs, Enemy_combat.cs (Ene), Enemy_Health.cs
-- Prefabs: Zombie_variant_01, Zombie_variant_01_Type_02, ZombieType03, Walk1, Boss
CREATE TABLE IF NOT EXISTS `enemy_types` (
    `type_id`                   VARCHAR(64)  NOT NULL            COMMENT 'Unique enemy type code. e.g. "ZOMBIE_VARIANT_01", "ZOMBIE_TYPE03", "BOSS_MUTATED". --> EnemyLifecycleDTO.enemyType',
    `display_name`              VARCHAR(100) NOT NULL            COMMENT 'Human-readable name shown in quest HUD, e.g. "Mutated Boss"',
    `base_health`               INT          NOT NULL            COMMENT 'Starting/maximum HP for this enemy type. --> Enemy_Health.maxhealth (5 for basic zombie)',
    `base_damage`               INT          NOT NULL            COMMENT 'Damage per attack. --> Enemy_combat.damage (1 for basic zombie)',
    `base_speed`                FLOAT        NOT NULL            COMMENT 'Chase movement speed. --> EnemyFollowPlayer.speed (2.0 for basic zombie)',
    `base_attack_range`         FLOAT        NOT NULL            COMMENT 'How close the enemy must be to land a hit. --> EnemyFollowPlayer.attackRange (1.2 for basic)',
    `base_detect_range`         FLOAT        NOT NULL            COMMENT 'How far the enemy can detect the player. --> EnemyFollowPlayer.playerdetectRange (5.0 for basic)',
    `base_attack_cooldown`      FLOAT        NOT NULL            COMMENT 'Seconds between attacks. --> EnemyFollowPlayer.attackCooldown (2.0 for basic)',
    `exp_reward`                INT          NOT NULL DEFAULT 3  COMMENT 'EXP granted when this enemy is killed. --> Enemy_Health.expReward',
    `is_boss`                   BOOLEAN      NOT NULL DEFAULT FALSE COMMENT 'TRUE if this enemy type is a boss. Bosses have nativeSpriteFacingSign=-1 and trigger BossManager.',
    `native_sprite_facing_sign` INT          NOT NULL DEFAULT 1  COMMENT '1 = sprite faces right natively (standard zombie). -1 = sprite faces left natively (boss). --> EnemyFollowPlayer.nativeSpriteFacingSign',
    `prefab_name`               VARCHAR(100) NULL                COMMENT 'Unity prefab asset name for spawning, e.g. "Zombie_variant_01". --> EnemyLifecycleDTO spawn reference',
    `spawn_weight`              INT          NOT NULL DEFAULT 1  COMMENT 'Relative probability of this type being chosen for random spawns. Higher = more common.',

    PRIMARY KEY (`type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Enemy type catalog — template stats for each enemy variant.';


-- Stores runtime instances of enemies in a world.
-- An "instance" is a specific enemy currently alive (or recently alive) in a world.
-- Its base stats come from enemy_types; only the DYNAMIC values are stored here.
-- Unity source: Enemy_Health.cs, EnemyFollowPlayer.cs, EnemyPositionDTO
CREATE TABLE IF NOT EXISTS `enemy_instances` (
    `enemy_id`          BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Unique ID for this specific enemy instance. Assigned by server. --> EnemyFollowPlayer.enemyId, EnemyPositionDTO.enemyId',
    `world_id`          VARCHAR(64)  NOT NULL                    COMMENT 'FK: worlds.id — which world this enemy exists in',
    `type_id`           VARCHAR(64)  NOT NULL                    COMMENT 'FK: enemy_types.type_id — what kind of enemy this is',

    -- Runtime values (change during gameplay — stored here, not in enemy_types)
    `current_health`    INT          NOT NULL                    COMMENT 'Current HP. Decreases as the enemy takes damage. --> Enemy_Health.currentHealth',
    `position_x`        FLOAT        NOT NULL DEFAULT 0.0        COMMENT 'Current X position in the world. --> EnemyPositionDTO.x',
    `position_y`        FLOAT        NOT NULL DEFAULT 0.0        COMMENT 'Current Y position in the world. --> EnemyPositionDTO.y',
    `facing_direction`  INT          NOT NULL DEFAULT 1          COMMENT '1 = right, -1 = left. --> EnemyPositionDTO.facingDirection',
    `enemy_state`       VARCHAR(16)  NOT NULL DEFAULT 'IDLE'     COMMENT 'Current AI state: IDLE, CHASING, ATTACKING. --> EnemyFollowPlayer.EnemyState enum',
    `is_alive`          BOOLEAN      NOT NULL DEFAULT TRUE       COMMENT 'FALSE once this enemy has been killed. Dead enemies are cleaned up but can be referenced by quest logs.',

    `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When this enemy instance was spawned',
    `updated_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last time this enemy state changed',

    PRIMARY KEY (`enemy_id`),
    CONSTRAINT `fk_enemy_inst_world` FOREIGN KEY (`world_id`) REFERENCES `worlds` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_enemy_inst_type`  FOREIGN KEY (`type_id`)  REFERENCES `enemy_types` (`type_id`)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Runtime enemy instances in a world — current health, position, state.';


-- ============================================================================
-- SECTION 7: BOSS ENCOUNTERS
-- ============================================================================

-- Tracks the state of the two-phase boss fight in a world.
-- A world has at most one active boss encounter at a time.
-- Phase 1 → Phase 2 transition: boss health first hits 0 → scream + restore to phase2_health + stat buffs.
-- Unity source: BossManager.cs, BossTriggerScript.cs, Enemy_Health.cs (boss phase system)
CREATE TABLE IF NOT EXISTS `boss_encounters` (
    `id`                        BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Surrogate PK',
    `world_id`                  VARCHAR(64)  NOT NULL                    COMMENT 'FK: worlds.id. Each world has exactly one boss encounter record.',
    `boss_enemy_id`             BIGINT       NULL                        COMMENT 'FK: enemy_instances.enemy_id. The specific enemy that IS the boss. NULL until spawned.',
    `fight_started`             BOOLEAN      NOT NULL DEFAULT FALSE      COMMENT 'TRUE once the player enters the boss trigger zone. --> BossManager.fightStarted',
    `current_phase`             INT          NOT NULL DEFAULT 1          COMMENT 'Current boss phase: 1 = normal, 2 = enraged. --> Enemy_Health.phase2Activated drives the 1→2 transition.',
    `phase2_activated`          BOOLEAN      NOT NULL DEFAULT FALSE      COMMENT 'TRUE once the boss has entered Phase 2 (enraged mode). --> Enemy_Health.phase2Activated',
    `phase2_health`             INT          NOT NULL DEFAULT 100        COMMENT 'HP the boss restores to when entering Phase 2. --> Enemy_Health.phase2Health',
    `phase2_speed_multiplier`   DOUBLE       NOT NULL DEFAULT 1.5        COMMENT 'Speed multiplier applied in Phase 2. --> Enemy_Health.phase2SpeedMultiplier',
    `is_defeated`               BOOLEAN      NOT NULL DEFAULT FALSE      COMMENT 'TRUE once the boss has been killed (only possible in Phase 2). --> BossManager.BossDefeated() is called.',
    `updated_at`                TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_boss_world` (`world_id`),
    CONSTRAINT `fk_boss_world`  FOREIGN KEY (`world_id`)       REFERENCES `worlds` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_boss_enemy`  FOREIGN KEY (`boss_enemy_id`)  REFERENCES `enemy_instances` (`enemy_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Boss encounter state per world — two-phase fight (normal → enraged → defeated).';


-- ============================================================================
-- SECTION 8: QUEST SYSTEM
-- ============================================================================

-- Tracks the Sara quest ("Clear the Village") per world.
-- The quest state machine: 0=NotStarted, 1=Active, 2=ObjectivesComplete, 3=HandedIn.
-- Unity source: SimpleQuestManager.cs, QuestUIHUD.cs, NPC_Talk.cs (Sara)
CREATE TABLE IF NOT EXISTS `quests` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Surrogate PK',
    `world_id`          VARCHAR(64)  NOT NULL                    COMMENT 'FK: worlds.id. Multiple quests per world via (world_id, quest_id) unique.',
    `quest_id`          VARCHAR(64)  NOT NULL DEFAULT 'sara_village' COMMENT 'Quest discriminator. Enables multiple quests per world: "sara_village", "quest2", etc.',
    `quest_state`       INT          NOT NULL DEFAULT 0          COMMENT 'Current quest phase. 0=NotStarted, 1=Active, 2=Complete, 3=HandedIn. --> SimpleQuestManager.QuestState',
    `zombies_remaining` INT          NOT NULL DEFAULT 12         COMMENT 'How many zombies the player still needs to kill. (Sara quest only) --> SimpleQuestManager.ZombiesRemaining',
    `is_boss_alive`     BOOLEAN      NOT NULL DEFAULT TRUE       COMMENT 'Whether the Mutated Boss has been killed. (Sara quest only) --> SimpleQuestManager.IsBossAlive',
    `objectives_json`   TEXT         NULL                        COMMENT 'Flexible JSON for quest-type-specific objectives. Quest2 uses this instead of hardcoded columns.',
    `updated_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_quest_world_quest` (`world_id`, `quest_id`),
    CONSTRAINT `fk_quest_world` FOREIGN KEY (`world_id`) REFERENCES `worlds` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Quest state per world — supports multiple quests per world via quest_id discriminator. Quest2 adds second questline.';


-- ============================================================================
-- SECTION 9: PERSISTENT OBJECTS (CROSS-SCENE DESTRUCTION TRACKING)
-- ============================================================================

-- Tracks which destructible/collectible objects have been removed in a world.
-- Prevents items from respawning and enemies from resurrecting when the player
-- leaves and re-enters a scene.
-- Unity source: ScenePersistentObject.cs, SimpleQuestManager.destroyedObjectIDs
CREATE TABLE IF NOT EXISTS `persistent_objects` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Surrogate PK',
    `world_id`          VARCHAR(64)  NOT NULL                    COMMENT 'FK: worlds.id — which world this destruction record belongs to',
    `object_unique_id`  VARCHAR(255) NOT NULL                    COMMENT 'The unique ID from ScenePersistentObject.uniqueID. Auto-generated as name_x_y if not manually set.',
    `is_destroyed`      BOOLEAN      NOT NULL DEFAULT TRUE       COMMENT 'TRUE = object has been destroyed/collected. Currently only destroyed objects are tracked.',
    `destroyed_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When this object was destroyed or collected',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_pobj_world_object` (`world_id`, `object_unique_id`),
    CONSTRAINT `fk_pobj_world` FOREIGN KEY (`world_id`) REFERENCES `worlds` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Destruction/collection records per world — prevents respawn across scene reloads.';


-- ============================================================================
-- SECTION 10: NPC & DIALOGUE SYSTEM
-- ============================================================================

-- Defines NPC actors (characters who can speak dialogue).
-- This is the "who speaks" catalog.
-- Unity source: ActorSO.cs, NPC_Talk.cs
CREATE TABLE IF NOT EXISTS `npc_actors` (
    `actor_id`              VARCHAR(64)  NOT NULL                COMMENT 'Unique actor identifier. e.g. "SARA", "JOEL". --> ActorSO.actorName',
    `actor_name`            VARCHAR(100) NOT NULL                COMMENT 'Display name shown in the dialogue UI. --> ActorSO.actorName, DialogueManager.actionName.text',
    `portrait_sprite_name`  VARCHAR(100) NULL                    COMMENT 'Identifier for the portrait sprite asset. --> ActorSO.portrait, DialogueManager.portrait.sprite',

    PRIMARY KEY (`actor_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='NPC actor catalog — who can speak in dialogues.';


-- Defines dialogue trees. Each tree is a sequence of lines followed by options.
-- A dialogue tree can be associated with a specific NPC and a specific quest state,
-- allowing different conversations based on game progress.
-- Unity source: DialogueSO.cs, DialogueManager.cs
CREATE TABLE IF NOT EXISTS `dialogue_trees` (
    `dialogue_id`       VARCHAR(64)  NOT NULL                    COMMENT 'Unique dialogue identifier. e.g. "SARA_INTRO", "SARA_WAITING", "SARA_COMPLETE". --> DialogueSO asset name',
    `npc_actor_id`      VARCHAR(64)  NULL                        COMMENT 'FK: npc_actors.actor_id. Which NPC owns this dialogue. NULL for system/narrator dialogues.',
    `quest_state_filter` INT         NULL                        COMMENT 'If not NULL, this dialogue is only used when QuestState matches this value. --> NPC_Talk routes by QuestState.',
    `description`       VARCHAR(255) NULL                        COMMENT 'Human-readable note for developers, e.g. "Sara intro dialogue before quest accepted"',

    PRIMARY KEY (`dialogue_id`),
    CONSTRAINT `fk_dtree_actor` FOREIGN KEY (`npc_actor_id`) REFERENCES `npc_actors` (`actor_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dialogue tree definitions — can be filtered by NPC and quest state.';


-- Individual lines within a dialogue tree.
-- Lines are played in order (line_index) before options appear.
-- Unity source: DialogueSO.Lines[], DialogueLine class
CREATE TABLE IF NOT EXISTS `dialogue_lines` (
    `id`            BIGINT       NOT NULL AUTO_INCREMENT         COMMENT 'Surrogate PK',
    `dialogue_id`   VARCHAR(64)  NOT NULL                        COMMENT 'FK: dialogue_trees.dialogue_id — which conversation this line belongs to',
    `line_index`    INT          NOT NULL                        COMMENT 'Order of this line within the dialogue. 0 = first line spoken. --> DialogueManager.dialogueIndex',
    `actor_id`      VARCHAR(64)  NOT NULL                        COMMENT 'FK: npc_actors.actor_id — who speaks this line. --> DialogueLine.actor',
    `line_text`     TEXT         NOT NULL                        COMMENT 'The actual dialogue text displayed. Supports Unity rich text tags. --> DialogueLine.text',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_dline_dialogue_index` (`dialogue_id`, `line_index`),
    CONSTRAINT `fk_dline_dialogue` FOREIGN KEY (`dialogue_id`) REFERENCES `dialogue_trees` (`dialogue_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_dline_actor`    FOREIGN KEY (`actor_id`)    REFERENCES `npc_actors` (`actor_id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Lines within a dialogue tree — spoken in order by specified actors.';


-- Branching options shown at the end of a dialogue tree.
-- Each option can lead to another dialogue tree or end the conversation (next_dialogue_id = NULL).
-- Unity source: DialogueSO.Options[], DialogueOption class, DialogueManager.showChoices()
CREATE TABLE IF NOT EXISTS `dialogue_options` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT     COMMENT 'Surrogate PK',
    `dialogue_id`       VARCHAR(64)  NOT NULL                    COMMENT 'FK: dialogue_trees.dialogue_id — which conversation these options belong to',
    `option_index`      INT          NOT NULL                    COMMENT 'Order of this option button. 0 = first button. --> DialogueManager.choicesButtons[i]',
    `option_text`       VARCHAR(255) NOT NULL                    COMMENT 'The text shown on the choice button. --> DialogueOption.optionText',
    `next_dialogue_id`  VARCHAR(64)  NULL                        COMMENT 'FK: dialogue_trees.dialogue_id. The conversation that starts if this option is chosen. NULL = end dialogue. --> DialogueOption.nextDialogue',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_dopt_dialogue_index` (`dialogue_id`, `option_index`),
    CONSTRAINT `fk_dopt_dialogue`      FOREIGN KEY (`dialogue_id`)      REFERENCES `dialogue_trees` (`dialogue_id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_dopt_next_dialogue` FOREIGN KEY (`next_dialogue_id`) REFERENCES `dialogue_trees` (`dialogue_id`)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Dialogue choice options — buttons that branch to other dialogues.';


-- ============================================================================
-- SECTION 11: MULTIPLAYER SESSIONS (LOBBY)
-- ============================================================================

-- Manages multiplayer game sessions (lobbies).
-- A session has a lifecycle: WAITING -> ACTIVE -> CLOSED.
-- Unity source: LobbyController, LobbyService, IGameAPI lobby methods
CREATE TABLE IF NOT EXISTS `sessions` (
    `session_id`    VARCHAR(64)  NOT NULL                        COMMENT 'Unique session identifier. --> LobbyResponse.sessionId, GameAPI.CurrentSessionId',
    `join_key`      VARCHAR(6)   NOT NULL                        COMMENT '6-character alphanumeric code the owner shares with the guest. --> LobbyResponse.joinKey',
    `status`        VARCHAR(16)  NOT NULL DEFAULT 'WAITING'      COMMENT 'Session state: WAITING, ACTIVE, CLOSED. Use AppConstants.STATUS_ constants. --> LobbyResponse.status',
    `owner_id`      BIGINT       NOT NULL                        COMMENT 'FK: players.id — the player who created the lobby. --> LobbyResponse.ownerId',
    `guest_id`      BIGINT       NULL                            COMMENT 'FK: players.id — the player who joined. NULL until join. --> LobbyResponse.guestId',
    `world_id`      VARCHAR(64)  NOT NULL                        COMMENT 'FK: worlds.id — which world this session is for. --> CreateLobbyRequest.worldId',
    `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (`session_id`),
    UNIQUE KEY `uk_sessions_join_key` (`join_key`),
    CONSTRAINT `fk_session_owner` FOREIGN KEY (`owner_id`) REFERENCES `players` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_session_guest` FOREIGN KEY (`guest_id`) REFERENCES `players` (`id`)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT `fk_session_world` FOREIGN KEY (`world_id`) REFERENCES `worlds` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Multiplayer session/lobby management — WAITING -> ACTIVE -> CLOSED lifecycle.';


-- ============================================================================
-- SECTION 12: INDEXES FOR PERFORMANCE
-- ============================================================================

-- These indexes speed up common queries beyond what PKs and FKs already cover.

-- Inventory: finding all items for a player (join through inventories)
CREATE INDEX `idx_inv_player_world` ON `inventories` (`player_id`, `world_id`);

-- Enemy instances: finding all enemies in a world (for spawn/despawn)
CREATE INDEX `idx_enemy_inst_world` ON `enemy_instances` (`world_id`, `is_alive`);

-- Persistent objects: checking if a specific object is destroyed
CREATE INDEX `idx_pobj_world` ON `persistent_objects` (`world_id`);

-- Dialogue: finding all dialogues for an NPC
CREATE INDEX `idx_dtree_actor` ON `dialogue_trees` (`npc_actor_id`);

-- Player world state: finding where a player is
CREATE INDEX `idx_pws_scene` ON `player_world_state` (`current_scene`);


-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
-- Next steps after running this schema:
--  1. Run wasteland_survivors_seed_v2.sql to populate initial data
--  2. Verify with: SHOW TABLES; DESCRIBE <table_name>;
--  3. Run the Spring Boot app — JPA will validate entity mappings against this schema
-- ============================================================================
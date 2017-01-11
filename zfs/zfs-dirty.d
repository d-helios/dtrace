#!/usr/sbin/dtrace -s 

txg-syncing
{
        this->dp = (dsl_pool_t *)arg0;
}

txg-syncing
/this->dp->dp_spa->spa_name == $$1/
{
        printf("%4dMB of %4dMB used", this->dp->dp_dirty_total / 1024 / 1024,
            `zfs_dirty_data_max / 1024 / 1024);
	
	start = timestamp;
}

txg-synced
/start && ((dsl_pool_t *)arg0)->dp_spa->spa_name == $$1/
{
        this->d = timestamp - start;
        printf("sync took %d.%02d seconds", this->d / 1000000000,
            this->d / 10000000 % 100);
}


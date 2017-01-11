#!/usr/sbin/dtrace -s

#pragma D option quiet

dtrace:::BEGIN
{
        printf("Tracing... Hit Ctrl-C to end.\n");
}


zfs_read:entry,zfs_write:entry {

         self->ts = timestamp;
         
         self->size = ((uio_t *)arg1)->uio_resid;
}


zfs_read:return,zfs_write:return /self->ts  / {
        this->fn = "";
        this->type =  probefunc == "zfs_write" ? "W" : "R";
        this->delta=(timestamp - self->ts)/1000;
        @zfs_latency[this->type] = quantize(this->delta);
/*      @zfs_iosize[this->type] = quantize(self->size); */
}


dtrace:::END
{
        printf("zfs latency distribution (us)\n");
        printa(@zfs_latency);

/*
        printf("\nzfs io size disctibution\n");
        printa(@zfs_iosize);
*/
}


#!/usr/sbin/dtrace -s
#pragma D option quiet

BEGIN
{
        printf("Start Tracing ...\n");
        start = timestamp;
}

fbt:zfs:zvol_read:entry,
fbt:zfs:zvol_write:entry
{
        self->ts = timestamp;
}

fbt:zfs:zvol_read:return,
fbt:zfs:zvol_write:return
/self->ts/
{
        delta = (timestamp - self->ts) /1000;
        @lat[probefunc] = quantize(delta);
        @avg[probefunc] = avg(delta);
        @stddev[probefunc] = stddev(delta);
        @iops[probefunc] = count();
}

END
{
        printf("Latency Histogramm in us\n");
        printa(@lat);

        normalize(@iops, (timestamp - start) / 1000000000);

        printf("%-30s %11s %11s %11s\n", "", "avg latency", "stddev",
            "iops");
        printa("%-30s %@9uus %@9uus %@9u/s \n", @avg, @stddev, @iops);

}


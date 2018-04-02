#!/usr/bin/bash


source $(dirname "$0")/ENV_FILE

/usr/sbin/dtrace -n '

#pragma D option quiet
#pragma D option defaultargs
#pragma D option dynvarsize=8m


iscsi:::xfer-start,
iscsi:::nop-receive
{
        self->ts = timestamp;
}

iscsi:::xfer-done
/args[2]->xfer_type == 0 && self->ts/
{
        @count_read[args[0]->ci_remote] = count();
        @bytes_read[args[0]->ci_remote] = sum(args[2]->xfer_len);
        @avg_bytes_read[args[0]->ci_remote] = avg(args[2]->xfer_len);
        delta=(timestamp - self->ts);
        @latency_read[args[0]->ci_remote] = avg(delta / 1000);
}

iscsi:::xfer-done
/args[2]->xfer_type == 1 && self->ts/
{
        @count_write[args[0]->ci_remote] = count();
        @bytes_write[args[0]->ci_remote] = sum(args[2]->xfer_len);
        @avg_bytes_write[args[0]->ci_remote] = avg(args[2]->xfer_len);
        delta=(timestamp - self->ts);
        @latency_write[args[0]->ci_remote] = avg(delta / 1000);
        @avg_aligned[args[0]->ci_remote] = avg((args[2]->xfer_loffset % 4096) ? 0 : 100);
}

iscsi:::nop-send
/self->ts/
{
        @count_nop[args[0]->ci_remote] = count();
        delta=(timestamp - self->ts);
        @latency_nop[args[0]->ci_remote] = avg(delta / 1000);
}

profile:::tick-14sec / ticks > 0 / { ticks--; }

profile:::tick-14sec
{
        printa("initiator=%s,operation=iops_read value=%@d\n", @count_read);
        printa("initiator=%s,operation=bytes_read value=%@d\n", @bytes_read);
        printa("initiator=%s,operation=latency_read value=%@d\n", @latency_read);

        printa("initiator=%s,operation=iops_write value=%@d\n", @count_write);
        printa("initiator=%s,operation=bytes_write value=%@d\n", @bytes_write);
        printa("initiator=%s,operation=latency_write value=%@d\n", @latency_write);

        printa("initiator=%s,operation=iops_nop value=%@d\n", @count_nop);
        printa("initiator=%s,operation=latency_nop value=%@d\n", @latency_nop);

        printa("initiator=%s,block=alignment value=%@d\n", @avg_aligned);

        printa("initiator=%s,block=avg_read_byte value=%@d\n", @avg_bytes_read);
        printa("initiator=%s,block=avg_write_byte value=%@d\n", @avg_bytes_write);

        trunc(@count_read); trunc(@bytes_read); trunc(@latency_read);
        trunc(@count_nop); trunc(@latency_nop);
        trunc(@count_write); trunc(@bytes_write); trunc(@latency_write);
        trunc(@avg_aligned); trunc(@avg_bytes_read); trunc(@avg_bytes_write);
}

profile:::tick-56sec {
        trunc(@count_read); trunc(@bytes_read); trunc(@latency_read);
        trunc(@count_nop); trunc(@latency_nop);
        trunc(@count_write); trunc(@bytes_write); trunc(@latency_write);
        trunc(@avg_aligned); trunc(@avg_bytes_read); trunc(@avg_bytes_write);

        exit(0);
} ' | \
        gawk -v hostname=$HOSTNAME -v influx_srv=$INFLUX_SRV '
/initiator/ {
        print("/usr/bin/curl -XPOST http://" influx_srv ":8086/write?db=znstor --data-binary \"iscsi_stats,hostname="hostname","$0"\"")
}
'

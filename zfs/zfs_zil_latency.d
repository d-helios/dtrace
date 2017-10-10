#!/usr/sbin/dtrace -s

#pragma D option quiet

dtrace:::BEGIN
{
        printf("Tracing... Hit Ctrl-C to end.\n");
}


::zil_commit:entry
{
        self->seq = args[0]->zl_lr_seq;
        self->ts = timestamp;
}

::zil_commit:return
/ self->seq && (this->delta = (timestamp - self->ts) / 1000) /
{
        @zil_latency["latency (us)"] = quantize(this->delta);
        this->delta = 0;
        self->ts = 0;
        self->seq = 0;
}

dtrace:::END
{
        printa(@zil_latency);
}

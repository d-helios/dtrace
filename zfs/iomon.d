/usr/sbin/dtrace -n '
#pragma D option quiet
#pragma D option defaultargs
/* 
#pragma D option aggsize=8m
#pragma D option bufsize=16m
#pragma D option dynvarsize=16m
#pragma D option aggrate=0
#pragma D option cleanrate=50Hz
*/
inline int    TICKS=$1;
inline string ADDR=$$2;

dtrace:::BEGIN
{
       TIMER = ( TICKS != NULL ) ?  TICKS : 1 ;
       ticks = TIMER;
       TITLE=10;
       title = 0;
}


/* ===================== beg NFS ================================= */
nfsv3:::op-read-start, nfsv3:::op-write-start ,nfsv4:::op-read-start {
        tm[args[1]->noi_xid] = timestamp;
        sz[args[1]->noi_xid] = args[2]->count    ;
}
nfsv4:::op-write-start {
        tm[args[1]->noi_xid] = timestamp;
        sz[args[1]->noi_xid] = args[2]->data_len ;
}
nfsv3:::op-read-done, nfsv3:::op-write-done, nfsv4:::op-read-done, nfsv4:::op-write-done
/tm[args[1]->noi_xid]/
{
        this->delta= (timestamp - tm[args[1]->noi_xid]);
        this->type =  probename == "op-write-done" ? "W" : "R";
        @nfs_tm[this->type]=sum(this->delta);
        @nfs_mx["R"]=max( (this->type == "R" ? this->delta : 0));
        @nfs_mx["W"]=max( (this->type == "W" ? this->delta : 0));
        @nfs_ct[this->type]=count();
        @nfs_sz[this->type]=sum(sz[args[1]->noi_xid]);
        tm[args[1]->noi_xid] = 0;
        sz[args[1]->noi_xid] = 0;
} /* --------------------- end NFS --------------------------------- */


/* ===================== beg ZFS ================================= */
zfs_read:entry,zfs_write:entry {
         self->ts = timestamp;
         self->filepath = args[0]->v_path;
         self->size = ((uio_t *)arg1)->uio_resid;
}
zfs_read:return,zfs_write:return /self->ts  / {
        this->fn= "";
        this->type =  probefunc == "zfs_write" ? "W" : "R";
        this->delta=(timestamp - self->ts) ;
        @zfs_tm[this->type]= sum(this->delta);
        @zfs_ct[this->type]=count();
        @zfs_sz[this->type]=sum(self->size);
        @zfs_mx["R"]=max( (this->type == "R" ? this->delta : 0));
        @zfs_mx["W"]=max( (this->type == "W" ? this->delta : 0));
        self->ts=0;
        self->filepath=0;
        self->size=0;
} /* --------------------- end ZFS --------------------------------- */


/* ===================== beg IO ================================= */
io:::start / arg0 != NULL && args[0]->b_addr != 0 / {
       tm_io[(struct buf *)arg0] = timestamp;
       sz_io[(struct buf *)arg0] = args[0]->b_bcount;
}
io:::done /tm_io[(struct buf *)arg0]/ {
      this->type = args[0]->b_flags & B_READ ? "R" : "W" ;
      this->delta = (( timestamp - tm_io[(struct buf *)arg0]));
       @io_tm[this->type]=sum(this->delta);
       @io_mx["R"]=max( (this->type == "R" ? this->delta : 0));
       @io_mx["W"]=max( (this->type == "W" ? this->delta : 0));
       @io_ct[this->type]=count();
       @io_sz[this->type]=sum(sz_io[(struct buf *)arg0]) ;
       sz_io[(struct buf *)arg0] = 0;
       tm_io[(struct buf *)arg0] = 0;
} /* --------------------- end IO --------------------------------- */



profile:::tick-1sec / ticks > 0 / { ticks--; }

profile:::tick-1sec
/ ticks == 0 /
{

       normalize(@nfs_tm,TIMER);
       normalize(@nfs_mx,TIMER);
       normalize(@nfs_ct,TIMER);
       normalize(@nfs_sz,TIMER);

       normalize(@io_tm,TIMER);
       normalize(@io_mx,TIMER);
       normalize(@io_ct,TIMER);
       normalize(@io_sz,TIMER);

       normalize(@zfs_tm,TIMER);
       normalize(@zfs_ct,TIMER);
       normalize(@zfs_sz,TIMER);
       normalize(@zfs_mx,TIMER);

       printa("nfs_tm ,%s,%@d\n",@nfs_tm);

       printa("nfs_tm ,%s,%@d\n",@nfs_tm);
       printa("nfs_mx ,%s,%@d\n",@nfs_mx);
       printa("nfs_ct ,%s,%@d\n",@nfs_ct);
       printa("nfs_sz ,%s,%@d\n",@nfs_sz);

       printa("io_tm  ,%s,%@d\n",@io_tm);
       printa("io_mx  ,%s,%@d\n",@io_mx);
       printa("io_ct  ,%s,%@d\n",@io_ct);
       printa("io_sz  ,%s,%@d\n",@io_sz);

       printa("zfs_tm ,%s,%@d\n",@zfs_tm);
       printa("zfs_ct ,%s,%@d\n",@zfs_ct);
       printa("zfs_sz ,%s,%@d\n",@zfs_sz);
       printa("zfs_mx ,%s,%@d\n",@zfs_mx);

       clear(@nfs_tm);
       clear(@nfs_ct);
       clear(@nfs_sz);

       clear(@io_tm);
       clear(@io_ct);
       clear(@io_sz);

       clear(@zfs_tm);
       clear(@zfs_ct);
       clear(@zfs_sz);

       clear(@io_mx);
       clear(@nfs_mx);
       clear(@zfs_mx);

       printf("!\n");

       ticks= TIMER;
}

/* use if you want to print something every TITLE lines */
profile:::tick-1sec / title <= 0 / { title=TITLE; }

' $1 $2   | \
perl -e '
$| = 1;
while (my $line = <STDIN>) {
       $line=~ s/\s+//g;
       if ( $line eq "!"  ) {
          printf("         |%11s|%10s|%10s|%10s|%10s|%10s\n",
                            "ms_8k",
                            "MB/s",
                            "avg_sz_kb",
                            "avg_ms",
                            "mx_ms",
                            "count"
                            );
          printf("---------|%11.11s|%10.10s|%10.10s|%10.10s|%10.10s|%10.10s\n",
                 "--------------------",
                 "--------------------",
                 "--------------------",
                 "--------------------",
                 "--------------------",
                 "--------------------");
          foreach $r_w ("R","W") {
#           foreach $io_type ("io","zfs","nfs","tcp") {
            foreach $io_type ("io","zfs","nfs") {
              foreach $var_type ("ct","sz","tm") {
                # if using cumulative values get old and do diff
                #       nfs               ct                  R
#               $old=${$io_type . "_" .  $var_type . "_old"}{$r_w}||0;
                $cur=${$io_type . "_" .  $var_type         }{$r_w}||0;
#               ${$var_type}=$cur - $old;
                ${$var_type}=$cur;
              }
              $mx=${$io_type . "_mx"}{$r_w}||0 ;
              $avg_sz_kb=0;
              $ms=0;
              $ms_8kb=0;
              if ( $ct > 0 ) {
                  $ms=(($tm/1000000)/$ct);
                  $avg_sz_kb=($sz/$ct)/1024;
              }
              if ( $sz > 0 ) {
                  $ms_8kb=(($tm/1000000)/($sz/(8*1024)));
              }
              $sz_MB=$sz/(1024*1024);
              $mx_ms=$mx/1000000;
              printf("%1s | %3s  :",$r_w,$io_type);
              printf(" %10.3f",$ms_8kb);
              printf(" %10.3f",$sz_MB);
              printf(" %10d",$avg_sz_kb);
              printf(" %10.2f",$ms);
              printf(" %10.2f",$mx_ms);
              printf(" %10d",$ct);
              print "\n";
           }
           if ( $r_w eq "R" ) { printf("---------\n"); }
         }
         $IOPS=$io_ct{"R"} + $io_ct{"W"};
         printf("IOPs  %10d\n",$IOPS);
         printf("----------------------------------------------------------------------------\n");
       } else {
          ($area, $r_w, $value)=split(",",$line);
          # if using cumulative values get old and do diff
#         $old=$area . "_old";
#         ${$old}{$r_w}=${$area}{$r_w};
#         ${$old}{$r_w}=${$area}{$r_w};
          ${$area}{$r_w}=$value;
       }
}'

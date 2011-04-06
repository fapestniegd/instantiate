package HTML::BlockParser;
################################################################################
# Yeah, I know there are already a bunch of HTML Parsers out there, but none
# of them parse HTML the way I do in my head. They seem to be glorified sed
# implementations, which is not what I want at all. I want a way to hold sub-
# blocks of html in anonymous data structs ({arrays,hashes} of {arrays,hashes})
# so I can inspect and massage them as I need to....
# 
# I'm not going after elegance or efficiency here, I'm going with parity of how
# my mind conceptualizes perl structs... Apparently my brain doesn't work like
# "real" perl developers at all. No new news there.
#
# It's just the way my mind works, Oh, and I abuse Data::Dumper and YAML::Dump
# when debugging, and having everything in an anonymous struct makes these tools
# work really well...
################################################################################
use HTML::Parser;
use Data::Dumper;
use YAML;
use strict;

sub new{
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'data'}=[];

    # construct the anonymous struct of the page in memory...
    $self->{'parser'} = HTML::Parser->new(
                                           api_version => 3,
                                           start_h => [
                                                        sub { $self->start(@_); }, 
                                                        "tagname, attr"
                                                      ],
                                           text_h   => [
                                                        sub { $self->text(@_); }, 
                                                        "dtext"
                                                      ],
                                           end_h   => [
                                                        sub { $self->end(@_); }, 
                                                        "tagname"
                                                      ],
                                           marked_sections => 1, 
                                         );
    $self->{'BAD_PARSE'}=0;
    bless($self, $class);
    return $self;
}

sub parse_err{
    my $self=shift;
    return $self->{'BAD_PARSE'};
}

#####################################################################
# passed an top-level-array-anon-struct traverse and get all <a>
# tags and return a list of { text=><subtext> attr=>a-tag's attr field
#####################################################################
sub list_links{
    my $self  = shift;
    my $block = shift if @_;
    my @links;
    foreach my $item (@{$block}){  
        if($item->{'tag'} eq 'a'){
           push(@links,{ 'text' => $self->subtext([$item]), 'href'=> $item->{'attr'}->{'href'} });
        } 
        if(defined($item->{'content'})){
            my @sublinks = $self->list_links($item->{'content'});
            push(@links,@sublinks) if($#sublinks > 0);
        }
    }
    return @links;
}

#####################################################################
# this takes a anon struct and traverses it to get all the text 
# out of the top block (and all sub-blocks) and returns it as a string
#####################################################################
sub subtext{
    my $self=shift;
    my $branch=shift if @_;
    my $text_string="";
    foreach my $item (@{$branch}){  
        $text_string.=$item->{'text'} if($item->{'text'});
        if(defined($item->{'content'})){
            $text_string.=$self->subtext($item->{'content'});
        }
    }
    $text_string=~s/\n/ /g;
    $text_string=~s/\s+$//g;
    return $text_string;
}
#####################################################################
# This dumps a table created by table_array to stdout
#####################################################################
sub dump_table_array{
    my $self=shift;
    my $table = shift if @_;
    #print Data::Dumper->Dump([$table]);
    my $debug=0;
    for(my $row=0;$row<=$#{ $table };$row++){
        print "|";
        for(my $col=0;$col<=($#{ $table->[$row] }) ;$col++){
            if($debug){
                print "########################## $row x $col #####################################\n";
                print Data::Dumper->Dump([$table->[$row]->[$col]]);
            }else{
                        my $colwidth=20;
                        if(defined($table->[$row]->[$col]->{'attr'}->{'colspan'})){
                            $colwidth=($colwidth*$table->[$row]->[$col]->{'attr'}->{'colspan'})+$table->[$row]->[$col]->{'attr'}->{'colspan'}-1;
                        }
                        my $text = $self->subtext([ $table->[$row]->[$col] ]);
                        $text=~s/\n/ /g;
                        print substr($text,0,$colwidth );
                        if(length($text) < $colwidth){
                            for(my $i=length($text);$i<$colwidth;$i++){ print " "; }
                        }
                        #print ref($table->[$row]->[$col]->{'attr'}->{'links'});
                        #print Data::Dumper->Dump([$table->[$row]->[$col]->{'attr'}->{'links'}]);
                        my $link_count=$#{ $table->[$row]->[$col]->{'links'} } + 1;
                        print "[$link_count]|";
                        #print "|";
                        #print Data::Dumper->Dump([$table->[$row]->[$col]]);
            }
        }
        print "\n";
    }
    return $self;
}


#####################################################################
# this takes a block of html that is inside a table tag and 
# converts it to $obj->[$row]->[$col]->{ attr=> value }
# it also creates a list of links under ->{'links'}
#####################################################################
sub table_array{
    my $self=shift;
    my $table_data=shift if @_;
    #print ref $table_data,"\n";
    my $table_array=[];

    if(!defined $table_data->{'tag'}){
        print STDERR "No table struct passed to table_array()\n";
        return undef;
    }elsif($table_data->{'tag'} ne 'table'){
        print STDERR "Not a table struct passed to table_array()\n";
        return undef;
    }else{
        # we know we're in a table, lets look for <tr>s
         foreach my $content (@{ $table_data->{'content'} }){
             my $columns=[];
             if($content->{'tag'} ne "tr"){
                 print STDERR "$content->{'tag'} is not a table row, omitting\n";
             }else{
                 foreach my $subcontent (@{ $content->{'content'} }){
                     if($subcontent->{'tag'} ne "td"){
                         print STDERR "$subcontent->{'tag'} is not a table data, omitting\n";
                     }else{
                         @{ $subcontent->{'links'} } = $self->list_links($subcontent->{'content'});
                         push(@{ $columns }, ($subcontent));
                     }
                 }
             }
             push(@{ $table_array },$columns);
         }
    }
    return $table_array;
}

sub get_blocks{
    my $self = shift;
    my $content = shift if @_;
    my $search_params = shift if @_;
    $self->{'pagebuf'} = [];
    $self->{'parser'}->parse($content);
    if($self->{'BAD_PARSE'}==1){
        open(BADPAGE, ">/tmp/badpage")||warn "could not open /tmp/badpage";
        print BADPAGE "$content";
        close(BADPAGE);
    }
    #print YAML::Dump($self->{'pagebuf'});

    ###########################################################
    # return all blocks of type 'block' to a list for inspection
    ###########################################################
    my @inspection_list;
    if(defined($search_params->{'block'})){
        $self->{'inspection_list'}=[];
        $self->walk_pagebuf($self->{'pagebuf'},$search_params->{'block'});
    }

    ###########################################################
    # create a list of tag_a:tag_b:tag_c:attributes that we 
    # can loop through to get matches on our search criteria
    #    ... There needs to be a document for this ...
    ###########################################################
    while(my $single_block=shift(@{ $self->{'inspection_list'} })){
        my @regexes=@{$search_params->{'match'}};
        my @patterns=$self->make_taglist([$single_block],'');
        while(my $pattern=shift(@patterns)){
            for(my $k=0;$k<=$#regexes;$k++){
                #print "$pattern=~m/^$search_params->{'block'}:$regexes[$k]/\n";
                if("$pattern" =~m/^$search_params->{'block'}:$regexes[$k]/){
                #print "********* MATCH *********\n";
                    splice(@regexes,$k,1);
                    $k=$#regexes;
                }
            }
        }
        if($#regexes < 0){
            push(@{ $self->{'matches'} },$single_block);
        }
    }
    return $self->{'matches'} if $self->{'matches'}; 
    return undef;
}

sub make_taglist{
    #######################################################
    # go through each block and sub block and create a 
    # string of tag:tag:tag:<text> 
    # (only show the text at the bottom element level)
    #######################################################
    my $self=shift;
    my $branch=shift if @_;
    my $prefix=shift if @_;
    my $taglist;
    my @alltags;
    foreach my $item (@{$branch}){ 
        $taglist="$item->{'tag'}:";
        if(defined($item->{'content'})){
            push(@alltags,$self->make_taglist($item->{'content'},"$prefix$taglist"));
        }
        if(defined($item->{'text'})){
            push(@alltags,"$prefix$item->{'tag'}:$item->{'text'}");
        }
    }
    return @alltags;
}

sub render_html{
    #######################################################
    # This renders a sub-set of the pages html, for debugs
    #######################################################
    my $self=shift;
    my $branch=shift if @_;
    my $indent=shift if @_;
    foreach my $item (@{$branch}){ 
        for(my $j=0;$j<$indent;$j++){ print "    "; }
        print "<$item->{'tag'}>\n";
        for(my $j=0;$j<=$indent;$j++){ print "    "; }
        print "$item->{'text'}\n";
        if(defined($item->{'content'})){
            $self->render_html($item->{'content'},$indent+1);
        }
        for(my $j=0;$j<$indent;$j++){ print "    "; }
        print "</$item->{'tag'}>\n";
    }
    return $self;
}

sub walk_pagebuf{
    my $self = shift;
    my $tag_tree = shift if @_;
    my $tag_type = shift if @_;
    foreach my $item (@{$tag_tree}){
        if($item->{'tag'} eq $tag_type){
            push(@{ $self->{'inspection_list'} } ,$item);
        }
        if(defined($item->{'content'})){
           $self->walk_pagebuf($item->{'content'} ,$tag_type);
        }
    }
    return $self;
}

sub start{
    my ($self, $tagname, $attr, $attrseq, $origtext) = @_;
    my $tolower=$tagname;
    $tolower=~tr/A-Z/a-z/;
    # If there is text in the buffer, and we're opening a tag, then its text outside a tag
    # we need to open a plaintext tag and then immediately close it.
    if($self->{'current_text'} ne ''){
       $self->{'current_text'}=~s/\t//g;
        my $struct = { 
                       'tag'     => 'plaintext',
                       'text'    => $self->{'current_text'}
                     };
    
        push(@{ $self->{'pagebuf'}->[$#{ $self->{'pagebuf'} }]->{'content'} },$struct) if $#{ $self->{'pagebuf'} }>=0;
        $self->{'current_text'}='';
    }
    my $struct = { 
                   'tag'     => $tolower,
                   'attr'    => $attr,
                   'attrseq' => $attrseq,
                   'origtxt' => $origtext
                 };
    # There will be no closing tag for these: so close them out immediately
    if(
        ($tolower eq "link")||
        ($tolower eq "input")||
        ($tolower eq "meta")||
        ($tolower eq "param")||
        ($tolower eq "embed")||
        ($tolower =~m/br\s*\/*/)||
        ($tolower eq "img")
      ){
         $self->{'current_text'}=~s/\t//g;
         $struct->{'text'}=$self->{'current_text'};
         $self->{'current_text'}='';
         push(@{ $self->{'pagebuf'}->[$#{ $self->{'pagebuf'} }]->{'content'} },$struct) if $#{ $self->{'pagebuf'} }>=0;
         return $self;
       }

    # center tags are unbalanced all the time,
    return $self if($tolower eq "center"); 
    push(@{ $self->{'pagebuf'} },$struct);
    return $self;
}

sub end{
    my ($self, $tagname, $origtext) = @_;
    my $tolower=$tagname;
    return $self if($tolower eq "center"); # center tags are unbalanced all the time
    $tolower=~tr/A-Z/a-z/;
    if($#{ $self->{'pagebuf'} } > 0){
        my $startstruct=pop(@{ $self->{'pagebuf'} });
        if($startstruct->{'tag'} ne $tolower){
            print STDERR "*** <$startstruct->{'tag'}> closed with <$tolower>. The page is not sane (unbalanced).\n";
            $self->{'BAD_PARSE'}=1;
        }else{
            $self->{'current_text'}=~s/\t//g;
            $startstruct->{'text'}=$self->{'current_text'};
            $self->{'current_text'}='';
            push(@{ $self->{'pagebuf'}->[$#{ $self->{'pagebuf'} }]->{'content'} },$startstruct) if $#{ $self->{'pagebuf'} }>=0;
        }
    }
    return $self;
}

sub text{
    my ($self, $origtext, $is_cdata) = @_;
    $origtext=~s/$//;
    $origtext=~s/\s*//;
    $self->{'current_text'}.=$origtext;
    return $self;
}

1;

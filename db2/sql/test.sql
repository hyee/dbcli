create type kilometers as integer with comparisons;
create type miles as integer with comparisons;
drop table travel;
create table travel(
    id char(9) not null,       
    kdistance tos.kilometers,      
    tomdistance tos.miles,           
    x DECIMAL(10,2),
    y Float(10),
    z Float,
    o DECIMAL(9),
    constraint pk_travel primary key(id));
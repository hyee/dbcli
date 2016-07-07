/*[[get session performance stats regarding to the input command. Usage: @@NAME <other command>
Examples:
    +------------------------------
    |@@NAME "ora actives"
    +------------------------------
    |@@NAME <<!
    |  show sga;
    |  ora actives
    |!
    +------------------------------
]]*/

snap sestime,sesstat begin 0
&V1
snap sestime,sesstat end
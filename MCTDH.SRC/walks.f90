

!! DETERMINES WHICH CONFIGURATIONS HAVE NONZERO MATRIX ELEMENTS WITH WHICH OTHERS, AND STORES INFORMATION
!!  ABOUT THE ORBITAL MATRIX ELEMENTS OF WHICH THEY ARE COMPRISED

#include "Definitions.INC"

function highspinorder(thisconfig)
  use parameters
  implicit none
  logical :: highspinorder
  integer :: thisconfig(ndof),ii,unpaired(numelec),flag,jj

  highspinorder=.true.

  unpaired(1:numelec)=1

  do ii=1,numelec
     do jj=1,numelec   !! WORKS
        if (jj.ne.ii) then   !!WORKS
! -xAVX error on lawrencium!  doesnt work this way.  compiler/instruction set bug.
!     do jj=ii+1,numelec   !!FAILS
           if (thisconfig(jj*2-1).eq.thisconfig(ii*2-1)) then
              unpaired(ii)=0
              unpaired(jj)=0
           endif
        endif     !!WORKS
     enddo
  enddo
  
  flag=0
  do ii=1,numelec
     if (unpaired(ii).eq.1) then
        if (thisconfig(ii*2).eq.1) then
           flag=1
        else
           if (flag==1) then
              highspinorder=.false.
              return
           endif
        endif
     endif
  enddo


end function highspinorder
   


function lowspinorder(thisconfig)
  use parameters
  implicit none
  logical :: lowspinorder
  integer :: thisconfig(ndof),ii,unpaired(numelec),flag,jj

  lowspinorder=.true.

  unpaired(:)=1

  do ii=1,numelec
!     do jj=ii+1,numelec    !!FAILS
     do jj=1,numelec        !!WORKS
        if (jj.ne.ii) then  !!WORKS
        if (thisconfig(jj*2-1).eq.thisconfig(ii*2-1)) then
           unpaired(ii)=0
           unpaired(jj)=0
        endif
        endif               !!WORKS
     enddo
  enddo

  flag=0
  do ii=1,numelec
     if (unpaired(ii).eq.1) then
        if (thisconfig(ii*2).eq.2) then
           flag=1
        else
           if (flag==1) then
              lowspinorder=.false.
           endif
        endif
     endif
  enddo


end function lowspinorder
        

subroutine walkalloc()
  use parameters
  use mpimod
  use configmod !! configlist for newconfigflag
  use walkmod
  implicit none
  logical :: highspinorder,lowspinorder

!! training wheels

  if (topconfig-botconfig.gt.0) then
     if (.not.highspinorder(configlist(:,topconfig))) then
        OFLWR "NOT HIGHSPIN",topconfig
        call printconfig(configlist(:,topconfig))
        CFLST
     endif
     if (.not.lowspinorder(configlist(:,botconfig))) then
        OFLWR "NOT LOWSPIN",botconfig
        call printconfig(configlist(:,topconfig))
        CFLST
     endif
  endif

!! 06-2015 configpserproc also in newconfig.f90

  allocate( numsinglewalks(configstart:configend) , numdoublewalks(configstart:configend) )
  allocate( numsinglediagwalks(configstart:configend) , numdoublediagwalks(configstart:configend) )

  call getnumwalks()
  OFLWR "Allocating singlewalks"; CFL
  allocate( singlewalk(maxsinglewalks,configstart:configend), singlediag(numelec,configstart:configend) )
  singlewalk=-1
  allocate( singlewalkdirphase(maxsinglewalks,configstart:configend) )
  singlewalkdirphase=0
  allocate( singlewalkopspf(1:2,maxsinglewalks,configstart:configend) )
  singlewalkopspf=-1
  OFLWR "Allocating doublewalks"; CFL
  allocate( doublewalkdirspf(1:4,maxdoublewalks,configstart:configend ) )
  doublewalkdirspf=-1
  allocate( doublewalkdirphase(maxdoublewalks,configstart:configend) )
  doublewalkdirphase=0
  allocate( doublewalk(maxdoublewalks,configstart:configend), doublediag(numelec*(numelec-1),configstart:configend) )
  doublewalk=-1
  OFLWR "     ..done walkalloc."; CFL
end subroutine walkalloc


subroutine walkdealloc()
  use parameters
  use walkmod
  implicit none
  deallocate( numsinglewalks,numsinglediagwalks )
  deallocate( numdoublewalks,numdoublediagwalks )
  deallocate( singlewalk )
  deallocate( singlewalkdirphase )
  deallocate( singlewalkopspf )
  deallocate( doublewalkdirspf )
  deallocate( doublewalkdirphase )
  deallocate( doublewalk)
end subroutine walkdealloc


subroutine configlistwrite()
  use parameters
  use configmod
  use mpimod
  implicit none

!! beforebarrier and afterbarrier in main

  if (myrank.eq.1) then
     open(1088,file=configlistfile,status="unknown",form="unformatted")
     write(1088) numconfig,ndof
     write(1088) configlist(:,:)
     close(1088)
  endif

end subroutine configlistwrite

subroutine configlistheaderread(iunit,readnumconfig,readndof)
  implicit none
  integer :: iunit,readnumconfig,readndof

  read(iunit) readnumconfig,readndof

end subroutine configlistheaderread


subroutine configlistread(iunit,readnumconfig,readndof, readconfiglist)

  implicit none
  integer :: iunit,readnumconfig,readndof, readconfiglist(readndof,readnumconfig)
  
  read(iunit) readconfiglist(:,:)

end subroutine configlistread



subroutine walks()
  use walkmod
  use configmod
  use parameters
  use aarrmod
  implicit none

  integer :: iindex, iiindex, jindex, jjindex,  ispin, jspin, iispin, jjspin, ispf, jspf, iispf, jjspf, config2, config1, dirphase, &
       iind, flag, idof, iidof, jdof, iwalk, reorder, getconfiguration,myiostat,getmval,idiag
!! DFALLOWED FOR SINGLE ELECTRON OPERATOR SINGLEWALKS (KEEP ALL FOR BIORTHO)
!! ALLOWEDCONFIG FOR TWO ELECTRON OPERATOR DOUBLEWALKS (KEEP ONLY WALKS FROM DFALLOWED)
  logical :: dfallowed, allowedconfig
  integer :: thisconfig(ndof), thatconfig(ndof), temporb(2), temporb2(2), isize, &
       listorder(maxdoublewalks+maxsinglewalks)

  !!  ***********   SINGLES  **********

  OFLWR "Calculating walks.  Singles...";  CFL
  
  do config1=botconfig,topconfig

     if (mod(config1,1000).eq.0) then
        OFLWR config1, " out of ", configend;        call closefile()
     endif

     iwalk=0
     thisconfig=configlist(:,config1)

     do idof=1,numelec   !! position in thisconfig that we're walking 

        temporb=thisconfig((idof-1)*2+1 : idof*2)
        ispf=temporb(1)
        ispin=temporb(2)
        iindex=iind(temporb)
        
        do jindex=1,spftot   !! the walk

           temporb=aarr(jindex,nspf)
           jspf=temporb(1)
           jspin=temporb(2)

           if (ispin.ne.jspin) then
              cycle
           endif
           
           flag=0
           do jdof=1,numelec
              if (jdof.ne.idof) then !! INCLUDING DIAGONAL WALKS
                 if (iind(thisconfig((jdof-1)*2+1:jdof*2)) == jindex) then 
                    flag=1
                 endif
              endif
           enddo

           if (flag.ne.0) then    ! pauli dis allowed configuration.
              cycle
           endif

           thatconfig=thisconfig
           thatconfig((idof-1)*2+1  : idof*2)=temporb

           dirphase=reorder(thatconfig)

!! KEEPING ALL SINGLE WALKS (FROM ALLOWED AND NOT ALLOWED)
!! FOR BIORTHO WITH ALLOWEDCONFIG() NOT DFALLOWED()

           if (.not.allowedconfig(thatconfig)) then
              cycle
           endif

           if (offaxispulseflag.eq.0.and.getmval(thatconfig).ne.getmval(thisconfig)) then
              cycle
           endif

           iwalk=iwalk+1
           singlewalkopspf(1:2,iwalk,config1)=[ ispf,jspf ]   !! ket, bra   bra is walk
           singlewalkdirphase(iwalk,config1)=dirphase
           
           config2=getconfiguration(thatconfig)
           
           singlewalk(iwalk,config1)=config2

        enddo   ! the walk
     enddo  ! position we're walking

     if (     numsinglewalks(config1) /= iwalk ) then
        OFLWR "WALK ERROR SINGLES.";        CFLST
     endif

  enddo   ! config1


  OFLWR "Calculating walks.  Doubles...";  call closefile()

  !!   ***********  DOUBLES  ************

  do config1=botconfig,topconfig

     if (mod(config1,1000).eq.0) then
        OFLWR config1, " out of ", configend;        CFL
     endif

     iwalk=0
     thisconfig=configlist(:,config1)

     do idof=1,numelec         !! positions in thisconfig that we're walking 
        do iidof=idof+1,numelec   !! 

           temporb=thisconfig((idof-1)*2+1 : idof*2)
           ispf=temporb(1)
           ispin=temporb(2)
           iindex=iind(temporb)

           temporb=thisconfig((iidof-1)*2+1 : iidof*2)
           iispf=temporb(1)
           iispin=temporb(2)
           iiindex=iind(temporb)

           do jindex=1,spftot   !! the walk
              
              temporb=aarr(jindex,nspf)
              jspf=temporb(1) 
              jspin=temporb(2)
              
              if (.not.ispin.eq.jspin) then
                 cycle
              endif

!! no more exchange separately

              do jjindex=1,spftot
                 if (jjindex.eq.jindex) then
                    cycle
                 endif
                 
                 temporb2=aarr(jjindex,nspf)
                 jjspf=temporb2(1)
                 jjspin=temporb2(2)
                 
                 if (.not.iispin.eq.jjspin) then
                    cycle
                 endif

                 flag=0
                 do jdof=1,numelec
                    if (jdof.ne.idof.and.jdof.ne.iidof) then !! INCLUDING DIAGONAL AND SINGLE WALKS
                       if ((iind(thisconfig((jdof-1)*2+1:jdof*2)) == jindex).or. &
                            (iind(thisconfig((jdof-1)*2+1:jdof*2)) == jjindex)) then
                          flag=1
                          exit
                       endif
                    endif
                 enddo
                 
                 if (flag.ne.0) then    ! pauli dis allowed configuration.
                    cycle
                 endif

                 
                 thatconfig=thisconfig
                 thatconfig((idof-1)*2+1  : idof*2)=temporb
                 thatconfig((iidof-1)*2+1  : iidof*2)=temporb2

                 dirphase=reorder(thatconfig)

!! KEEPING DOUBLE WALKS ONLY FROM ALLOWED CONFIGS
!! WITH DFALLOWED() NOT ALLOWEDCONFIG()

                 if (.not.dfallowed(thatconfig)) then
                    cycle
                 endif

                 if (offaxispulseflag.eq.0.and.getmval(thatconfig).ne.getmval(thisconfig)) then
                    cycle
                 endif

                 
                 iwalk = iwalk+1
            
!!                                                      ket2   bra2   ket1   bra1
                 doublewalkdirspf(1:4,iwalk,config1)=[ iispf, jjspf, ispf, jspf ]
                 doublewalkdirphase(iwalk,config1)=dirphase
                 
                 config2=getconfiguration(thatconfig)
                 doublewalk(iwalk,config1)=config2

              enddo   ! the walk
           enddo
           
        enddo  ! position we're walking
     enddo

     if (     numdoublewalks(config1) /= iwalk ) then
        OFLWR "WALK ERROR DOUBLES.",config1,numdoublewalks(config1),iwalk; CFLST
     endif

  enddo   ! config1

  call mpibarrier()

  if (sortwalks.ne.0) then

     OFLWR "Sorting walks..."; CFL
     do config1=botconfig,topconfig
        
        call getlistorder(singlewalk(:,config1),listorder(:),numsinglewalks(config1))
        call listreorder(singlewalkdirphase(:,config1),listorder(:),numsinglewalks(config1),1)
        call listreorder(singlewalkopspf(:,:,config1),listorder(:),numsinglewalks(config1),2)
        call listreorder(singlewalk(:,config1),listorder(:),numsinglewalks(config1),1)

        call getlistorder(doublewalk(:,config1),listorder(:),numdoublewalks(config1))
        call listreorder(doublewalkdirphase(:,config1),listorder(:),numdoublewalks(config1),1)
        call listreorder(doublewalkdirspf(:,:,config1),listorder(:),numdoublewalks(config1),4)
        call listreorder(doublewalk(:,config1),listorder(:),numdoublewalks(config1),1)
     enddo
     OFLWR "    .... done sorting walks."; CFL
  endif

  call mpibarrier()

  if (sparseconfigflag.eq.0.and.maxsinglewalks.ne.0) then
     isize=2*maxsinglewalks
     call mpiallgather_i(singlewalkopspf,   numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
     isize=maxsinglewalks
     call mpiallgather_i(singlewalkdirphase,numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
     call mpiallgather_i(singlewalk,        numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
  endif


  if (sparseconfigflag.eq.0.and.maxdoublewalks.ne.0) then
     isize=4*maxdoublewalks
     call mpiallgather_i(doublewalkdirspf,  numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
     isize=maxdoublewalks
     call mpiallgather_i(doublewalkdirphase,numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
     call mpiallgather_i(doublewalk,        numconfig*isize,configsperproc(:)*isize,maxconfigsperproc*isize)
  endif




  do config1=configstart,configend
     idiag=0
     do iwalk=1,numsinglewalks(config1)
        if (singlewalk(iwalk,config1).eq.config1) then
           idiag=idiag+1
           singlediag(idiag,config1)=iwalk
        endif
     enddo
     numsinglediagwalks(config1)=idiag
     idiag=0
     do iwalk=1,numdoublewalks(config1)
        if (doublewalk(iwalk,config1).eq.config1) then
           idiag=idiag+1
           doublediag(idiag,config1)=iwalk
        endif
     enddo
     numdoublediagwalks(config1)=idiag
  enddo
     
  
end subroutine walks



subroutine getnumwalks()
  use walkmod
  use configmod
  use parameters
  use mpimod
  use aarrmod
  implicit none

  integer :: iindex, iiindex, jindex, jjindex,  ispin, jspin, iispin, jjspin, ispf, iispf,  config1,innumconfig,  &
       dirphase, iind, flag, idof, iidof, jdof,iwalk , reorder, myiostat, inprocs , getmval

!! DFALLOWED FOR SINGLE ELECTRON OPERATOR SINGLEWALKS (KEEP ALL FOR BIORTHO)
!! ALLOWEDCONFIG FOR TWO ELECTRON OPERATOR DOUBLEWALKS (KEEP ONLY WALKS FROM DFALLOWED)
  logical :: dfallowed, allowedconfig
  integer :: thisconfig(ndof), thatconfig(ndof), temporb(2), temporb2(2),totwalks
  character(len=3) :: iilab
  character(len=4) :: iilab0

  if (nprocs.gt.999) then
  print *, "redim getnumwalks";  call mpistop()
  endif

  write(iilab0,'(I4)') myrank+1000
  iilab(:)=iilab0(2:4)
  

  !!  ***********   SINGLES  **********

  call mpibarrier()

     OFLWR "Counting walks. Singles";  CFL

     do config1=botconfig,topconfig

        iwalk=0
        thisconfig=configlist(:,config1)
        
        do idof=1,numelec   !! position in thisconfig that we're walking 
           
           temporb=thisconfig((idof-1)*2+1 : idof*2)
           ispf=temporb(1)
           ispin=temporb(2)
           iindex=iind(temporb)
           
           do jindex=1,spftot   !! the walk
              
              temporb=aarr(jindex,nspf)
              jspin=temporb(2)
              if (ispin.ne.jspin) then  
                 cycle
              endif

              flag=0
              do jdof=1,numelec
                 if (jdof.ne.idof) then !! INCLUDING DIAGONAL WALKS
                    if (iind(thisconfig((jdof-1)*2+1:jdof*2)) == jindex) then 
                       flag=1
                    endif
                 endif
              enddo
              
              if (flag.ne.0) then    ! pauli dis allowed configuration.
                 cycle
              endif

              thatconfig=thisconfig
              thatconfig((idof-1)*2+1  : idof*2)=temporb

              dirphase=reorder(thatconfig)

!! KEEPING ALL SINGLE WALKS (FROM ALLOWED AND NOT ALLOWED)
!! FOR BIORTHO WITH ALLOWEDCONFIG() NOT DFALLOWED()

              if (.not.allowedconfig(thatconfig)) then
                 cycle
              endif

              if (offaxispulseflag.eq.0.and.getmval(thatconfig).ne.getmval(thisconfig)) then
                 cycle
              endif
              
              iwalk=iwalk+1

           enddo   ! the walk
        enddo  ! position we're walking
        
        numsinglewalks(config1) = iwalk 
        
     enddo   ! config1

     if (sparseconfigflag.eq.0) then
        call mpiallgather_i(numsinglewalks(:),numconfig,configsperproc(:),maxconfigsperproc)
     endif


     OFLWR "Counting walks. Doubles"; CFL
     
  !!   ***********  DOUBLES  ************

     do config1=botconfig,topconfig
        if (mod(config1,1000).eq.0) then
           OFLWR config1, " out of ", configend;        call closefile()
        endif
        
        iwalk=0
        thisconfig=configlist(:,config1)
        
        do idof=1,numelec         !! positions in thisconfig that we're walking 
           do iidof=idof+1,numelec   !! 
              
              temporb=thisconfig((idof-1)*2+1 : idof*2)
              ispf=temporb(1)
              ispin=temporb(2)
              iindex=iind(temporb)
              
              temporb=thisconfig((iidof-1)*2+1 : iidof*2)
              iispf=temporb(1)
              iispin=temporb(2)
              iiindex=iind(temporb)
              
              do jindex=1,spftot   !! the walk

                 temporb=aarr(jindex,nspf)
                 jspin=temporb(2)

                 if (.not.ispin.eq.jspin) then
                    cycle
                 endif

!! no more exchange separately
                 do jjindex=1,spftot   !! the walk
                    if (jjindex.eq.jindex) then
                       cycle
                    endif

                    temporb2=aarr(jjindex,nspf)
                    jjspin=temporb2(2)

                    if (.not.iispin.eq.jjspin) then
                       cycle
                    endif

                    flag=0
                    do jdof=1,numelec
                       if (jdof.ne.idof.and.jdof.ne.iidof) then  !! INCLUDING DIAGONAL AND SINGLE WALKS
                          if ((iind(thisconfig((jdof-1)*2+1:jdof*2)) == jindex).or. &
                               (iind(thisconfig((jdof-1)*2+1:jdof*2)) == jjindex)) then
                             flag=1
                          endif
                       endif
                    enddo
                    
                    if (flag.ne.0) then    ! pauli dis allowed configuration.
                       cycle
                    endif
                    
                    thatconfig=thisconfig
                    thatconfig((idof-1)*2+1  : idof*2)=temporb
                    thatconfig((iidof-1)*2+1  : iidof*2)=temporb2
                    dirphase=reorder(thatconfig)

!! KEEPING DOUBLE WALKS ONLY FROM ALLOWED CONFIGS
!! WITH DFALLOWED() NOT ALLOWEDCONFIG()

                    if (dfallowed(thatconfig)) then
                       if (offaxispulseflag.ne.0.or.getmval(thatconfig).eq.getmval(thisconfig)) then
                          iwalk = iwalk+1
                       endif
                    endif
                    
                 enddo   ! the walk
              enddo
           enddo  ! position we're walking
        enddo
        
        numdoublewalks(config1)=iwalk
        
     enddo   ! config1

     if (sparseconfigflag.eq.0) then
        call mpiallgather_i(numdoublewalks(:),numconfig,configsperproc(:),maxconfigsperproc)
     endif


  maxsinglewalks=0;  maxdoublewalks=0

  totwalks=0
  do config1=configstart,configend

     if (maxsinglewalks.lt.numsinglewalks(config1)) then
        maxsinglewalks=numsinglewalks(config1)
     endif
     if (maxdoublewalks.lt.numdoublewalks(config1)) then
        maxdoublewalks=numdoublewalks(config1)
     endif

     totwalks=totwalks+numsinglewalks(config1)+numdoublewalks(config1)

  enddo

  if (sparseconfigflag.ne.0) then
     call mympiireduceone(totwalks)
  endif
  call mympiimax(maxsinglewalks);  call mympiimax(maxdoublewalks)


  OFLWR;  write(mpifileptr, *) "Maximum number of"
  write(mpifileptr, *) "           single walks= ",  maxsinglewalks
  write(mpifileptr, *) "           double walks= ",  maxdoublewalks;  
  WRFL "  TOTAL walks:", totwalks,"maxdoublewalks*numconfig",maxdoublewalks*numconfig
  WRFL; CFL

end subroutine getnumwalks





subroutine getlistorder(values, order,num)
  use fileptrmod
  implicit none
  integer :: num, values(num),taken(num), order(num)
  integer :: i,j,whichlowest, flag, lowval

  taken=0;  order=-1
  do j=1,num
     whichlowest=-1; flag=0;     lowval=10000000  !! is not used (see flag)
     do i=1,num
        if ( taken(i) .eq. 0 ) then
           if ((flag.eq.0) .or.(values(i) .le. lowval)) then
              flag=1;              lowval=values(i); whichlowest=i
           endif
        endif
     enddo
     if ((whichlowest.gt.num).or.(whichlowest.lt.1)) then
         OFLWR taken,"lowest ERROR, J=",j," WHICHLOWEST=", whichlowest;   CFLST
     endif
     if (taken(whichlowest).ne.0) then
        OFLWR "TAKENmm ERROR.";        CFLST
     endif
     taken(whichlowest)=1;     order(j)=whichlowest
  enddo

end subroutine getlistorder


subroutine listreorder(list, order,num,numper)
  implicit none
  integer :: num, numper, list(numper,num),order(num),newvals(numper,num),j

  do j=1,num
     newvals(:,j)=list(:,order(j))
  enddo

  list(:,:)=newvals(:,:)

end subroutine listreorder






!! ORBITAL AND CONFIGURATION MATRIX ELEMENTS.  TWO ELECTRON REDUCED MATRIX ELEMENTS
!! ARE CALCULATED HERE ALONG THE WAY.  GET_REDUCEDHAM MUST BE CALLED AFTER TWOE_MATEL
!! BECAUSE IT NEEDS THOSE REDUCED MATRIX ELEMENTS

#include "Definitions.INC"


subroutine all_matel()
  use parameters
  use xxxmod
  use mpimod
  use configmod
  use opmod
  implicit none
  integer,save :: times(10)=0,xcalled=0
  integer :: itime,jtime,getlen
  xcalled=xcalled+1

  call all_matel0(yyy%cptr(0), yyy%cmfpsivec(spfstart,0), yyy%cmfpsivec(spfstart,0), twoereduced,times)

  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...called all_matel0 in all_matel"; CFL; call mpibarrier()
  endif

  call system_clock(itime)
  if (sparseopt.ne.0) then
     call assemble_sparsemats(www,yyy%cptr(0),yyy%sptr(0),1,1,1,1)
     if (use_dfwalktype) then
        call assemble_sparsemats(dfww,yyy%cptr(0),yyy%sdfptr(0),1,1,1,1)
     endif
  endif
  call system_clock(jtime); times(5)=times(5)+jtime-itime

  if ((myrank.eq.1).and.(notiming.eq.0)) then
     if (xcalled==1) then
        open(853, file=timingdir(1:getlen(timingdir)-1)//"/matel.time.dat", status="unknown")
!!$        open(8853, file=timingdir(1:getlen(timingdir)-1)//"/matel.abs.time.dat", status="unknown")
        write(853,'(100A11)')   "op", "pot", "pulse", "two", "assemble"
!!$        write(8853,'(100A11)')   "matel absolute timing"
        close(853)
!!$        close(8853)
     endif

     open(853, file=timingdir(1:getlen(timingdir)-1)//"/matel.time.dat", status="unknown", position="append")
     write(853,'(100I11)')  times(1:5)/1000;        close(853)
     close(853)
!!$     call system("date >> "//timingdir(1:getlen(timingdir)-1)//"/matel.abs.time.dat")
  endif

  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...finished all_matel"; CFL; call mpibarrier()
  endif

end subroutine all_matel

subroutine all_matel0(matrix_ptr,inspfs1,inspfs2,twoereduced,times)
  use parameters
  use configptrmod
  implicit none
  Type(CONFIGPTR) :: matrix_ptr
  DATATYPE :: inspfs1(spfsize,nspf), inspfs2(spfsize,nspf), twoereduced(reducedpotsize,nspf,nspf)
  integer :: times(*), i,j

  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...sparseops_matel"; CFL; call mpibarrier()
  endif
  call system_clock(i)
  call sparseops_matel(matrix_ptr,inspfs1,inspfs2)
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...pot_matel"; CFL; call mpibarrier()
  endif
  call system_clock(j);  times(1)=times(1)+j-i; i=j
  call pot_matel(matrix_ptr,inspfs1,inspfs2)
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...pulse_matel"; CFL; call mpibarrier()
  endif
  call system_clock(j);  times(2)=times(2)+j-i; i=j
  call pulse_matel(matrix_ptr,inspfs1,inspfs2)
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...twoe_matel"; CFL; call mpibarrier()
  endif
  call system_clock(j);  times(3)=times(3)+j-i; i=j
  call twoe_matel(matrix_ptr,inspfs1,inspfs2,twoereduced)
  call system_clock(j);  times(4)=times(4)+j-i
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "     ...done all_matel0"; CFL; call mpibarrier()
  endif

end subroutine all_matel0

subroutine twoe_matel(matrix_ptr,inspfs1,inspfs2,twoereduced)
  use parameters
  use mpimod
  use configptrmod
  implicit none
  Type(CONFIGPTR) :: matrix_ptr
  DATATYPE :: inspfs1(spfsize,nspf),inspfs2(spfsize,nspf),twoereduced(reducedpotsize,nspf,nspf)

  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "         In twoe_matel.  Calling call_twoe_matel"; CFL; call mpibarrier()
  endif
  call call_twoe_matel(inspfs1,inspfs2,matrix_ptr%xtwoematel(:,:,:,:),twoereduced,timingdir,notiming)
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "         Done call_twoe_matel.  Reduce"; CFL; call mpibarrier()
  endif
  if (parorbsplit.eq.3) then
     call mympireduce(matrix_ptr%xtwoematel(:,:,:,:),nspf**4)
  endif
  if (debugflag.eq.42) then
     call mpibarrier();     OFLWR "         Done reduce, done twoe_matel."; CFL; call mpibarrier()
  endif

end subroutine twoe_matel

subroutine pot_matel(matrix_ptr,inspfs1,inspfs2)
  use parameters
  use configptrmod
  implicit none
  Type(CONFIGPTR) :: matrix_ptr
  integer :: j
  DATATYPE :: inspfs1(spfsize,nspf), inspfs2(spfsize,nspf),  ttempspfs(spfsize,nspf),tempmatel(nspf,nspf)

  matrix_ptr%xpotmatel(:,:)=0d0

  do j=1,nspf
     call mult_pot(inspfs2(:,j),ttempspfs(:,j))
  enddo

!! potmatel is proper ordering.  fast index is conjg.

  call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfs, spfsize, DATAZERO, matrix_ptr%xpotmatel(:,:), nspf)

  call hatom_matel(inspfs1,inspfs2,tempmatel, nspf)

  matrix_ptr%xpotmatel(:,:)=matrix_ptr%xpotmatel(:,:)+ tempmatel(:,:)

  if (numfrozen.gt.0) then
!! only call of op_frozen_exchange.

     ttempspfs=0d0
     call op_frozen_exchange(inspfs2,ttempspfs)
     do j=1,nspf
        call op_frozenreduced(inspfs2(:,j),ttempspfs(:,j))   !! ADDS to ttempspfs
     enddo

     call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfs, spfsize, DATAONE, matrix_ptr%xpotmatel(:,:) ,nspf)
  endif

  if (parorbsplit.eq.3) then
     call mympireduce(matrix_ptr%xpotmatel(:,:),nspf**2)
  endif

end subroutine pot_matel



subroutine pulse_matel(matrix_ptr,inspfs1,inspfs2)
  use parameters
  use configptrmod
  implicit none
  Type(CONFIGPTR) :: matrix_ptr
  integer :: ispf
  DATATYPE :: inspfs1(spfsize,nspf), inspfs2(spfsize,nspf), nullcomplex(1), dipoles(3)
  DATATYPE :: ttempspfsxx(spfsize,nspf), ttempspfsyy(spfsize,nspf), ttempspfszz(spfsize,nspf)

  matrix_ptr%xpulsematelxx=0.d0;     matrix_ptr%xpulsematelyy=0.d0;     matrix_ptr%xpulsematelzz=0.d0

  if (velflag.eq.0) then

     do ispf=1,nspf
        call lenmultiply(inspfs2(:,ispf),ttempspfsxx(:,ispf), DATAONE,DATAZERO,DATAZERO)
        call lenmultiply(inspfs2(:,ispf),ttempspfsyy(:,ispf), DATAZERO,DATAONE,DATAZERO)
        call lenmultiply(inspfs2(:,ispf),ttempspfszz(:,ispf), DATAZERO,DATAZERO,DATAONE)
     enddo
  else
     call velmultiply(nspf,inspfs2(:,:),ttempspfsxx(:,:), DATAONE,DATAZERO,DATAZERO)
     call velmultiply(nspf,inspfs2(:,:),ttempspfsyy(:,:), DATAZERO,DATAONE,DATAZERO)
     call velmultiply(nspf,inspfs2(:,:),ttempspfszz(:,:), DATAZERO,DATAZERO,DATAONE)
  endif
!! pulsematel is proper order.

  dipoles(:)=0d0
  if (velflag.eq.0) then
     call nucdipvalue(nullcomplex,dipoles)
  endif

  call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfsxx, spfsize, DATAONE, matrix_ptr%xpulsematelxx(:,:) ,nspf)
  call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfsyy, spfsize, DATAONE, matrix_ptr%xpulsematelyy(:,:) ,nspf)
  call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfszz, spfsize, DATAONE, matrix_ptr%xpulsematelzz(:,:) ,nspf)
  matrix_ptr%xpulsenuc(:)=dipoles(:)

  if (parorbsplit.eq.3) then
     call mympireduce(matrix_ptr%xpulsematelxx(:,:),nspf**2)
     call mympireduce(matrix_ptr%xpulsematelyy(:,:),nspf**2)
     call mympireduce(matrix_ptr%xpulsematelzz(:,:),nspf**2)
  endif

end subroutine pulse_matel


subroutine sparseops_matel(matrix_ptr,inspfs1,inspfs2)
  use parameters
  use configptrmod
  implicit none
  Type(CONFIGPTR) :: matrix_ptr
  integer :: ispf  
  DATATYPE :: inspfs1(spfsize,nspf), inspfs2(spfsize,nspf)  , ttempspfs(spfsize,nspf)  

  matrix_ptr%xopmatel=0d0;  matrix_ptr%xymatel=0d0;  

  if (multmanyflag.ne.0) then
     call mult_ke(inspfs2(:,:),ttempspfs(:,:),nspf,timingdir,notiming)
  else
     do ispf=1,nspf
        call mult_ke(inspfs2(:,ispf),ttempspfs(:,ispf),1,timingdir,notiming)
     enddo
  endif

  call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfs, spfsize, DATAZERO, matrix_ptr%xopmatel(:,:) ,nspf)

  if (nonuc_checkflag/=1) then
     call noparorbsupport("op_yderiv")
     do ispf=1,nspf
        call op_yderiv(inspfs2(:,ispf),ttempspfs(:,ispf))
     enddo
     call MYGEMM(CNORMCHAR,'N',nspf,nspf, spfsize, DATAONE, inspfs1, spfsize, ttempspfs, &
          spfsize, DATAZERO, matrix_ptr%xymatel(:,:) ,nspf)
  endif

  if (parorbsplit.eq.3) then
     call mympireduce(matrix_ptr%xopmatel(:,:),nspf**2)
  endif

end subroutine sparseops_matel


!! direct (not exchange)

subroutine frozen_matels()
  use parameters
  implicit none

  call call_frozen_matels()

end subroutine frozen_matels


!! ADDS TO OUTSPFS

subroutine op_frozen_exchange(inspfs,outspfs)
  use parameters
  implicit none
  DATATYPE :: inspfs(spfsize,nspf)
  DATATYPE :: outspfs(spfsize,nspf)

  call call_frozen_exchange(inspfs,outspfs)

end subroutine op_frozen_exchange


subroutine arbitraryconfig_matel_singles00transpose(www,onebodymat, smallmatrixtr)
  use fileptrmod
  use sparse_parameters
  use walkmod
  implicit none
  type(walktype),intent(in) :: www
  integer ::    config1,  iwalk,myind,ihop
  DATATYPE :: onebodymat(www%nspf,www%nspf), &
       smallmatrixtr(www%singlematsize,www%configstart:www%configend)

  smallmatrixtr=0d0; 

  do config1=www%botconfig,www%topconfig
     do ihop=1,www%numsinglehops(config1)
        do iwalk=www%singlehopwalkstart(ihop,config1),www%singlehopwalkend(ihop,config1)

!!$     do iwalk=1,www%numsinglewalks(config1)

           if (sparseconfigflag.eq.0) then
              myind=www%singlewalk(iwalk,config1)
           else
              myind=ihop
           endif
           smallmatrixtr(myind,config1)=smallmatrixtr(myind,config1)+   &
                onebodymat(www%singlewalkopspf(1,iwalk,config1), &
                www%singlewalkopspf(2,iwalk,config1)) *  &
                www%singlewalkdirphase(iwalk,config1)
        enddo
     enddo
  enddo

  if (sparseconfigflag.eq.0) then
     call mpiallgather(smallmatrixtr(:,:),www%numconfig**2,www%configsperproc(:)*www%numconfig,www%maxconfigsperproc*www%numconfig)
  endif

end subroutine arbitraryconfig_matel_singles00transpose



subroutine arbitraryconfig_matel_doubles00transpose(www,twobodymat, smallmatrixtr)
  use sparse_parameters
  use fileptrmod
  use walkmod
  implicit none
  type(walktype),intent(in) :: www
  integer ::    config1, iwalk,myind,ihop
  DATATYPE :: twobodymat(www%nspf,www%nspf,www%nspf,www%nspf), &
       smallmatrixtr(www%doublematsize,www%configstart:www%configend)

  smallmatrixtr=0d0;

  do config1=www%botconfig,www%topconfig

     do ihop=1,www%numdoublehops(config1)
        do iwalk=www%doublehopwalkstart(ihop,config1),www%doublehopwalkend(ihop,config1)

!!$     do iwalk=1,www%numdoublewalks(config1)

           if (sparseconfigflag.eq.0) then
              myind=www%doublewalk(iwalk,config1)
           else
              myind=ihop
           endif
           smallmatrixtr(myind,config1)=smallmatrixtr(myind,config1) + &           
                twobodymat(www%doublewalkdirspf(1,iwalk,config1), &
                www%doublewalkdirspf(2,iwalk,config1),   &
                www%doublewalkdirspf(3,iwalk,config1),   &
                www%doublewalkdirspf(4,iwalk,config1))* &
                www%doublewalkdirphase(iwalk,config1) 
        enddo
     enddo
  enddo

  if (sparseconfigflag.eq.0) then
     call mpiallgather(smallmatrixtr(:,:),www%numconfig**2,www%configsperproc(:)*www%numconfig,www%maxconfigsperproc*www%numconfig)
  endif

end subroutine arbitraryconfig_matel_doubles00transpose



subroutine assemble_dfbasismat(www,outmatrix, matrix_ptr, boflag, nucflag, pulseflag, conflag, time,imc)
  use sparse_parameters
  use r_parameters
  use fileptrmod
  use configptrmod
  use walkmod
  implicit none
  type(walktype),intent(in) :: www
  Type(configptr),intent(in) :: matrix_ptr
  integer,intent(in) :: nucflag, pulseflag, conflag, boflag,imc
  DATATYPE,intent(out) ::        outmatrix(www%numdfbasis*numr,www%numdfbasis*numr)
  real*8,intent(in) :: time
  DATATYPE, allocatable ::        bigmatrix(:,:),halfmatrix(:,:),halfmatrix2(:,:),donematrix(:,:)

  if (sparseconfigflag/=0) then
     OFLWR "Error, assemble_full_config_matel called when sparseconfigflag/=0";CFLST
  endif
  
  allocate(  bigmatrix(www%numconfig*numr,www%numconfig*numr), halfmatrix(www%numdfbasis*numr,www%numconfig*numr),halfmatrix2(www%numconfig*numr,www%numdfbasis*numr), donematrix(www%numdfbasis*numr,www%numdfbasis*numr))

  bigmatrix(:,:)=0d0; halfmatrix(:,:)=0d0; halfmatrix2(:,:)=0d0; donematrix(:,:)=0d0; outmatrix(:,:)=0d0

  call assemble_configmat(www,bigmatrix,matrix_ptr,boflag,nucflag,pulseflag,conflag,time,imc)

!! obviously not good to transform for each r; should transform earlier. 

  call basis_transformto_all(www,www%numconfig*numr*numr,bigmatrix,halfmatrix2)
  halfmatrix=TRANSPOSE(halfmatrix2)
  call basis_transformto_all(www,www%numdfbasis*numr*numr,halfmatrix,donematrix)
  outmatrix=transpose(donematrix)

  deallocate(bigmatrix,halfmatrix,halfmatrix2,donematrix)

end subroutine assemble_dfbasismat



!! FOR NONSPARSE (HERE, ASSEMBLE_CONFIGMAT) INCLUDE A-SQUARED TERM.

subroutine assemble_configmat(www,bigconfigmat,matrix_ptr, boflag, nucflag, pulseflag, conflag,time,imc)
  use fileptrmod
  use sparse_parameters
  use ham_parameters
  use r_parameters
  use configptrmod
  use walkmod
  use opmod   !! rkemod, proderivmod, frozenkediag, frozenpotdiag, bondpoints, bondweights
  implicit none
  type(walktype),intent(in) :: www
  Type(CONFIGPTR),intent(in) :: matrix_ptr
  integer,intent(in) :: conflag,boflag,nucflag,pulseflag,imc
  real*8,intent(in) :: time
  DATATYPE,intent(out) :: bigconfigmat(numr,www%numconfig,numr,www%numconfig)
  DATATYPE :: tempmatel(www%nspf,www%nspf)
  DATATYPE, allocatable :: tempconfigmat(:,:),tempconfigmat2(:,:),diagmat(:,:,:)
  real*8 :: gg
  DATATYPE :: facs(3), csum0,csum
  integer :: ir,jr,i

  if (sparseconfigflag.ne.0) then
     OFLWR "BADDDCALLL"; CFLST
  endif

  allocate(tempconfigmat(www%numconfig,www%numconfig),tempconfigmat2(www%numconfig,www%numconfig), &
       diagmat(www%numconfig,www%numconfig,numr))

  diagmat(:,:,:)=0d0

  call vectdpot(time,velflag,facs,imc)

  if (boflag==1) then
     do ir=1,numr
        do i=1,www%numconfig

         diagmat(i,i,ir)=( frozenkediag/bondpoints(ir)**2 + (nucrepulsion+frozenpotdiag)/bondpoints(ir) + energyshift ) * matrix_ptr%kefac 

        enddo
     enddo

     call arbitraryconfig_matel_doubles00transpose(www,matrix_ptr%xtwoematel(:,:,:,:),tempconfigmat)
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xpotmatel(:,:),tempconfigmat2)

     tempconfigmat(:,:) = TRANSPOSE( tempconfigmat(:,:) + tempconfigmat2(:,:) )
     do ir=1,numr
        diagmat(:,:,ir)=diagmat(:,:,ir)+tempconfigmat(:,:)/bondpoints(ir)
     enddo
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xopmatel(:,:),tempconfigmat)
     tempconfigmat(:,:)=TRANSPOSE(tempconfigmat(:,:))
     do ir=1,numr
        diagmat(:,:,ir)=diagmat(:,:,ir)+tempconfigmat(:,:)/bondpoints(ir)**2
     enddo
  endif

  if (conflag==1.and.constraintflag.ne.0) then
     tempmatel(:,:)=matrix_ptr%xconmatel(:,:)
     if (tdflag.ne.0) then
        tempmatel(:,:)=tempmatel(:,:)+matrix_ptr%xconmatelxx(:,:)*facs(1)
        tempmatel(:,:)=tempmatel(:,:)+matrix_ptr%xconmatelyy(:,:)*facs(2)
        tempmatel(:,:)=tempmatel(:,:)+matrix_ptr%xconmatelzz(:,:)*facs(3)
     endif
     call arbitraryconfig_matel_singles00transpose(www,tempmatel,tempconfigmat)
     tempconfigmat(:,:)=TRANSPOSE(tempconfigmat(:,:))
     do ir=1,numr
        diagmat(:,:,ir)=diagmat(:,:,ir)-tempconfigmat(:,:)
     enddo
  endif

  if ((pulseflag.eq.1.and.tdflag.eq.1)) then
     tempmatel(:,:)= matrix_ptr%xpulsematelxx*facs(1)+ &
          matrix_ptr%xpulsematelyy*facs(2)+ &
          matrix_ptr%xpulsematelzz*facs(3)
     call arbitraryconfig_matel_singles00transpose(www,tempmatel,tempconfigmat)
     tempconfigmat(:,:)=TRANSPOSE(tempconfigmat(:,:))
     do ir=1,numr
        if (velflag.eq.0) then
           diagmat(:,:,ir)=diagmat(:,:,ir)+tempconfigmat(:,:)*bondpoints(ir)
        else
           diagmat(:,:,ir)=diagmat(:,:,ir)+tempconfigmat(:,:)/bondpoints(ir)
        endif
     enddo

!! A-SQUARED TERM...  looked ok for z polarization.  number of electrons times a-squared.  fac of 2 needed apparently.
!!   for length... need nuclear dipole too.

!!   for velocity ...  also need derivative operator in bond length for hetero !!!!  TO DO !!!!


        gg=0.25d0


     if (velflag.ne.0) then 
        csum0 = matrix_ptr%kefac * www%numelec * (facs(1)**2 + facs(2)**2 + facs(3)**2) * 2  * gg   !! a-squared term.
     else
!! xpulsenuc is nuclear dipole, divided by R.    from nucdipvalue.

        csum0 = (matrix_ptr%xpulsenuc(1) * facs(1) + matrix_ptr%xpulsenuc(2) * facs(2) + matrix_ptr%xpulsenuc(3) * facs(3) )
     endif
     
     do ir=1,numr
        if (velflag.eq.0) then
           csum=bondpoints(ir) *csum0
        else
           csum=   csum0    !! A-squared !!    no R factor !!
        endif
        do i=1,www%numconfig
           diagmat(i,i,ir)=diagmat(i,i,ir) + csum 
        enddo
     enddo
  endif   !! pulse

  bigconfigmat(:,:,:,:)=0d0

  do ir=1,numr
     bigconfigmat(ir,:,ir,:)=diagmat(:,:,ir)
  enddo

  if (nonuc_checkflag.eq.0.and.nucflag.eq.1) then
       call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xymatel,tempconfigmat)   !! fills in all, wasteful
       tempconfigmat(:,:)=TRANSPOSE(tempconfigmat(:,:))

     do ir=1,numr
        do jr=1,numr
           bigconfigmat(ir,:,jr,:)=bigconfigmat(ir,:,jr,:)+tempconfigmat(:,:)*proderivmod(ir,jr)
        enddo
     enddo
     do i=1,www%numconfig
        bigconfigmat(:,i,:,i)=bigconfigmat(:,i,:,i) + rkemod(:,:)*matrix_ptr%kefac
     enddo
  endif

  deallocate(tempconfigmat,tempconfigmat2,diagmat)

end subroutine assemble_configmat


!! NO A-SQUARED TERM HERE; TIME IS NOT AN ARGUMENT.  A-squared in sparsesparsemult_byproc.

subroutine assemble_sparsemats(www,matrix_ptr, sparse_ptr,boflag, nucflag, pulseflag, conflag)
  use fileptrmod
  use r_parameters
  use sparse_parameters
  use ham_parameters
  use configptrmod
  use walkmod
  use sparseptrmod
  use opmod   !! rkemod, proderivmod
  implicit none
  type(walktype),intent(in) :: www
  integer :: conflag,boflag,nucflag,pulseflag
  Type(CONFIGPTR) :: matrix_ptr
  Type(SPARSEPTR) :: sparse_ptr

  if (sparseconfigflag.eq.0) then
     OFLWR "BADDDCAL555LL"; CFLST
  endif

  if (boflag==1) then
     call arbitraryconfig_matel_doubles00transpose(www,matrix_ptr%xtwoematel(:,:,:,:),sparse_ptr%xpotsparsemattr(:,:))
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xpotmatel(:,:),sparse_ptr%xonepotsparsemattr(:,:))
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xopmatel(:,:),sparse_ptr%xopsparsemattr(:,:))
  endif

  if (conflag==1.and.constraintflag.ne.0) then
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xconmatel,sparse_ptr%xconsparsemattr)
     if (tdflag.ne.0) then
        call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xconmatelxx,sparse_ptr%xconsparsemattrxx)
        call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xconmatelyy,sparse_ptr%xconsparsemattryy)
        call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xconmatelzz,sparse_ptr%xconsparsemattrzz)
     endif
  endif

  if ((pulseflag.eq.1.and.tdflag.eq.1)) then
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xpulsematelxx,sparse_ptr%xpulsesparsemattrxx)
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xpulsematelyy,sparse_ptr%xpulsesparsemattryy)
     call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xpulsematelzz,sparse_ptr%xpulsesparsemattrzz)
  endif
  if (nonuc_checkflag.eq.0.and.nucflag.eq.1) then
       call arbitraryconfig_matel_singles00transpose(www,matrix_ptr%xymatel,sparse_ptr%xysparsemattr)
  endif

end subroutine assemble_sparsemats


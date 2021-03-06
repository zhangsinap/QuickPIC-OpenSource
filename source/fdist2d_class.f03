! fdist2d class for QuickPIC Open Source 1.0
! update: 04/18/2016

      module fdist2d_class

      use perrors_class
      use parallel_pipe_class
      use spect2d_class
      use ufield2d_class
      use input_class

      implicit none

      private

      public :: fdist2d, fdist2d_000

      type, abstract :: fdist2d

         private

         class(spect2d), pointer, public :: sp => null()
         class(perrors), pointer, public :: err => null()
         class(parallel_pipe), pointer, public :: p => null()
!
! ndprof = profile type 
         integer :: npf, npmax
                          
         contains
         generic :: new => init_fdist2d         
         generic :: del => end_fdist2d
         generic :: dist => dist2d
         procedure(ab_init_fdist2d), deferred, private :: init_fdist2d
         procedure, private :: end_fdist2d
         procedure(ab_dist2d), deferred, private :: dist2d
         procedure :: getnpf, getnpmax
                  
      end type fdist2d

      abstract interface
!
      subroutine ab_dist2d(this,part2d,npp,fd,s)
         import fdist2d
         import ufield2d
         implicit none
         class(fdist2d), intent(inout) :: this
         real, dimension(:,:), pointer, intent(inout) :: part2d
         integer, intent(inout) :: npp
         class(ufield2d), intent(in), pointer :: fd         
         real, intent(in) :: s
      end subroutine ab_dist2d
!
      subroutine ab_init_fdist2d(this,input,i)
         import fdist2d
         import input_json
         implicit none
         class(fdist2d), intent(inout) :: this
         type(input_json), intent(inout), pointer :: input
         integer, intent(in) :: i
      end subroutine ab_init_fdist2d
!
      end interface

      type, extends(fdist2d) :: fdist2d_000

         private
! xppc, yppc = particle per cell in x and y directions
         integer :: xppc, yppc
         real :: qm, den
         character(len=:), allocatable :: long_prof
         real, dimension(:), allocatable :: s, fs
                          
         contains
         procedure, private :: init_fdist2d => init_fdist2d_000
         procedure, private :: dist2d => dist2d_000
                  
      end type fdist2d_000


      character(len=10), save :: class = 'fdist2d:'
      character(len=128), save :: erstr
      
      contains
!
      function getnpf(this)

         implicit none

         class(fdist2d), intent(in) :: this
         integer :: getnpf
         
         getnpf = this%npf
      
      end function getnpf
!      
      function getnpmax(this)

         implicit none

         class(fdist2d), intent(in) :: this
         integer :: getnpmax
         
         getnpmax = this%npmax
      
      end function getnpmax
!
      subroutine end_fdist2d(this)
          
         implicit none
         
         class(fdist2d), intent(inout) :: this
         character(len=18), save :: sname = 'end_fdist2d:'

         call this%err%werrfl2(class//sname//' started')
         call this%err%werrfl2(class//sname//' ended')
                  
      end subroutine end_fdist2d
!      
      subroutine init_fdist2d_000(this,input,i)
      
         implicit none
         
         class(fdist2d_000), intent(inout) :: this
         type(input_json), intent(inout), pointer :: input
         integer, intent(in) :: i
! local data
         integer :: npf,xppc,yppc,npmax,indx,indy
         real :: qm, den
         character(len=20) :: sn,s1
         character(len=18), save :: sname = 'init_fdist2d_000:'
         
         this%sp => input%sp
         this%err => input%err
         this%p => input%pp

         call this%err%werrfl2(class//sname//' started')
         write (sn,'(I3.3)') i
         s1 = 'species('//trim(sn)//')'
         call input%get('simulation.indx',indx)
         call input%get('simulation.indy',indy)
         call input%get(trim(s1)//'.profile',npf)
         call input%get(trim(s1)//'.ppc(1)',xppc)
         call input%get(trim(s1)//'.ppc(2)',yppc)
         call input%get(trim(s1)//'.q',qm)
         call input%get(trim(s1)//'.density',den)
         npmax = xppc*yppc*(2**indx)*(2**indy)/this%p%getlnvp()*4
         call input%get(trim(s1)//'.longitudinal_profile',this%long_prof)
         if (trim(this%long_prof) == 'piecewise') then
            call input%get(trim(s1)//'.piecewise_density',this%fs)
            call input%get(trim(s1)//'.piecewise_s',this%s)
         end if
         this%npf = npf
         this%xppc = xppc
         this%yppc = yppc
         this%qm = qm
         this%den = den
         this%npmax = npmax
         call this%err%werrfl2(class//sname//' ended')

      end subroutine init_fdist2d_000
!
      subroutine dist2d_000(this,part2d,npp,fd,s)
         implicit none
         class(fdist2d_000), intent(inout) :: this
         real, dimension(:,:), pointer, intent(inout) :: part2d
         integer, intent(inout) :: npp
         class(ufield2d), intent(in), pointer :: fd
         real, intent(in) :: s 
! local data
         character(len=18), save :: sname = 'dist2d_000:'
         real, dimension(:,:), pointer :: pt => null()
         integer :: nps, nx, ny, noff, xppc, yppc, i, j
         integer :: ix, iy
         real :: qm, den_temp
         integer :: prof_l

         call this%err%werrfl2(class//sname//' started')
         
         nx = fd%getnd1p(); ny = fd%getnd2p(); noff = fd%getnoff()
         xppc = this%xppc; yppc = this%yppc
         den_temp = 1.0
         if (trim(this%long_prof) == 'piecewise') then
            prof_l = size(this%fs)
            if (s<this%s(1) .or. s>this%s(prof_l)) then
               write (erstr,*) 'The s is out of the bound!'
               call this%err%equit(class//sname//erstr)
               return
            end if
            do i = 2, prof_l
               if (this%s(i) < this%s(i-1)) then
                  write (erstr,*) 's is not monotonically increasing!'
                  call this%err%equit(class//sname//erstr)
                  return
               end if
               if (s<=this%s(i)) then
                  den_temp = this%fs(i-1) + (this%fs(i)-this%fs(i-1))/&
                  &(this%s(i)-this%s(i-1))*(s-this%s(i-1))
                  exit
               end if
            end do
         end if
         qm = den_temp*this%den*this%qm/abs(this%qm)/real(xppc)/real(yppc)
         nps = 1
         pt => part2d
! initialize the particle positions
         if (noff < ny) then
         do i=2, nx-1
            do j=2, ny
               do ix = 0, xppc-1
                  do iy=0, yppc-1
                     pt(1,nps) = (ix + 0.5)/xppc + i - 1
                     pt(2,nps) = (iy + 0.5)/yppc + j - 1 + noff
                     pt(3,nps) = 0.0
                     pt(4,nps) = 0.0
                     pt(5,nps) = 0.0
                     pt(6,nps) = 1.0
                     pt(7,nps) = 1.0
                     pt(8,nps) = qm
                     nps = nps + 1
                  enddo
               enddo
            enddo
         enddo
         else if (noff > (nx-ny-1)) then       
         do i=2, nx-1
            do j=1, ny-1
               do ix = 0, xppc-1
                  do iy=0, yppc-1
                     pt(1,nps) = (ix + 0.5)/xppc + i - 1
                     pt(2,nps) = (iy + 0.5)/yppc + j - 1 + noff
                     pt(3,nps) = 0.0
                     pt(4,nps) = 0.0
                     pt(5,nps) = 0.0
                     pt(6,nps) = 1.0
                     pt(7,nps) = 1.0
                     pt(8,nps) = qm
                     nps = nps + 1
                  enddo
               enddo
            enddo
         enddo
         else
         do i=2, nx-1
            do j=1, ny
               do ix = 0, xppc-1
                  do iy=0, yppc-1
                     pt(1,nps) = (ix + 0.5)/xppc + i - 1
                     pt(2,nps) = (iy + 0.5)/yppc + j - 1 + noff
                     pt(3,nps) = 0.0
                     pt(4,nps) = 0.0
                     pt(5,nps) = 0.0
                     pt(6,nps) = 1.0
                     pt(7,nps) = 1.0
                     pt(8,nps) = qm
                     nps = nps + 1
                  enddo
               enddo
            enddo
         enddo
         endif
         
         npp = nps - 1
         
         call this%err%werrfl2(class//sname//' ended')

      end subroutine dist2d_000
!
      end module fdist2d_class
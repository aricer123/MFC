!>
!! @file m_precision_select.f90
!! @brief Contains module m_precision_select

!> @brief This file contains the definition of floating point used in MFC
module m_precision_select
#ifdef MFC_MPI
    use mpi                    !< Message passing interface (MPI) module
#endif

    implicit none

    integer, parameter :: single_precision = selected_real_kind(6, 37)
    integer, parameter :: double_precision = selected_real_kind(15, 307)

    integer, parameter :: wp = double_precision
#ifdef MFC_MPI
    integer, parameter :: mpi_p = MPI_DOUBLE_PRECISION
#else
    integer, parameter :: mpi_p = -100
#endif

end module m_precision_select